# frozen_string_literal: true

require "rails_helper"

RSpec.describe ProjectedGroupStandingsQuery do
  let(:tournament) { create(:tournament) }
  let(:user) { create(:user) }

  def team(name)
    create(:team, tournament: tournament, name: name)
  end

  # A group-stage match; passing scores marks it finished, otherwise scheduled.
  def group_match(group, home, away, home_score: nil, away_score: nil)
    finished = !home_score.nil?
    create(:match, tournament: tournament, phase: "group_stage", group: group,
                   home_team: home, away_team: away,
                   status: finished ? "finished" : "scheduled",
                   home_score: home_score || 0, away_score: away_score || 0)
  end

  def predict(match, home, away, by: user)
    create(:prediction, user: by, match: match,
                        predicted_home_score: home, predicted_away_score: away)
  end

  def group_named(result, name)
    result.find { |g| g.name == name }
  end

  def row_for(group, team)
    group.standings.find { |row| row.team == team }
  end

  it "blends finished results with the user's predictions and ranks on the blended values" do
    a = team("A")
    b = team("B")
    c = team("C")
    d = team("D")
    group_match("A", a, b, home_score: 2, away_score: 0)  # official: A beats B
    predict(group_match("A", c, d), 3, 1)                 # predicted: C beats D
    predict(group_match("A", b, c), 0, 0)                 # predicted: draw

    group = group_named(described_class.call(tournament: tournament, user: user), "A")

    # Official-only counters for A; blended goals/points everywhere.
    expect(row_for(group, a)).to have_attributes(
      played: 1, won: 1, drawn: 0, lost: 0,
      goals_for: 2, goals_against: 0, goal_difference: 2, points: 3
    )
    # C: 0 played (nothing official) but predicted win + predicted draw => 4 pts.
    expect(row_for(group, c)).to have_attributes(
      played: 0, won: 0, drawn: 0, lost: 0,
      goals_for: 3, goals_against: 1, goal_difference: 2, points: 4
    )
    # B: official loss counts fully; predicted draw adds 1 pt, no played.
    expect(row_for(group, b)).to have_attributes(
      played: 1, won: 0, drawn: 0, lost: 1,
      goals_for: 0, goals_against: 2, goal_difference: -2, points: 1
    )
    # Ranking on blended points: C(4) > A(3) > B(1) > D(0).
    expect(group.standings.map(&:team)).to eq([ c, a, b, d ])
    expect(group.standings.map(&:position)).to eq([ 1, 2, 3, 4 ])
  end

  it "projects a fully predicted, unplayed group: zero played but predicted points and order (pre-tournament hybrid)" do
    x = team("X")
    y = team("Y")
    z = team("Z")
    predict(group_match("B", x, y), 2, 1) # X beats Y
    predict(group_match("B", y, z), 1, 1) # draw
    predict(group_match("B", x, z), 0, 3) # Z beats X

    group = group_named(described_class.call(tournament: tournament, user: user), "B")

    expect(group.standings).to all(have_attributes(played: 0, won: 0, drawn: 0, lost: 0))
    # Z: 4 pts (win + draw), X: 3 pts, Y: 1 pt.
    expect(row_for(group, z)).to have_attributes(points: 4, goals_for: 4, goals_against: 1, goal_difference: 3)
    expect(row_for(group, x)).to have_attributes(points: 3, goals_for: 2, goals_against: 4, goal_difference: -2)
    expect(row_for(group, y)).to have_attributes(points: 1, goals_for: 2, goals_against: 3, goal_difference: -1)
    expect(group.standings.map(&:team)).to eq([ z, x, y ])
  end

  it "excludes unfinished matches the user did not predict (teams still listed at zero)" do
    m = team("M")
    n = team("N")
    group_match("C", m, n) # scheduled, no prediction

    group = group_named(described_class.call(tournament: tournament, user: user), "C")

    expect(group.standings.map(&:team)).to contain_exactly(m, n)
    expect(group.standings).to all(have_attributes(played: 0, points: 0, goals_for: 0, goals_against: 0))
  end

  it "ignores other users' predictions" do
    p = team("P")
    q = team("Q")
    predict(group_match("D", p, q), 5, 0, by: create(:user))

    group = group_named(described_class.call(tournament: tournament, user: user), "D")

    expect(group.standings).to all(have_attributes(points: 0, goals_for: 0))
  end

  it "lets the official result replace the prediction once the match finishes (convergence)" do
    r = team("R")
    s = team("S")
    match = group_match("E", r, s, home_score: 0, away_score: 1) # official: S beats R
    predict(match, 4, 0)                                        # stale prediction: R thrashes S

    group = group_named(described_class.call(tournament: tournament, user: user), "E")

    # Only the official result counts — the prediction contributes nothing.
    expect(row_for(group, r)).to have_attributes(played: 1, lost: 1, points: 0, goals_for: 0, goals_against: 1)
    expect(row_for(group, s)).to have_attributes(played: 1, won: 1, points: 3, goals_for: 1, goals_against: 0)
  end

  it "loads the user's predictions in a single query across all groups" do
    e = team("E1")
    f = team("F1")
    g = team("G1")
    h = team("H1")
    predict(group_match("F", e, f), 1, 0)
    predict(group_match("G", g, h), 2, 2)

    prediction_queries = 0
    counter = lambda do |_name, _start, _finish, _id, payload|
      prediction_queries += 1 if payload[:sql].include?("FROM \"predictions\"")
    end

    ActiveSupport::Notifications.subscribed(counter, "sql.active_record") do
      described_class.call(tournament: tournament, user: user)
    end

    expect(prediction_queries).to eq(1)
  end
end
