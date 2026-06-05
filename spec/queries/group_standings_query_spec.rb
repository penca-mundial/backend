# frozen_string_literal: true

require "rails_helper"

RSpec.describe GroupStandingsQuery do
  let(:tournament) { create(:tournament) }

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

  def group_named(result, name)
    result.find { |g| g.name == name }
  end

  it "computes stats from finished matches and ranks by points then goal difference" do
    a = team("A")
    b = team("B")
    c = team("C")
    d = team("D")
    group_match("A", a, b, home_score: 2, away_score: 0) # A beats B
    group_match("A", a, c, home_score: 1, away_score: 0) # A beats C
    group_match("A", b, c, home_score: 3, away_score: 0) # B beats C
    group_match("A", d, a)                               # unplayed: D appears, nothing counted

    group = group_named(described_class.call(tournament: tournament), "A")

    # A:6 pts, B:3, then D(0 pts, GD 0) outranks C(0 pts, GD -4).
    expect(group.standings.map(&:team)).to eq([ a, b, d, c ])
    expect(group.standings.first).to have_attributes(
      team: a, position: 1, played: 2, won: 2, drawn: 0, lost: 0,
      goals_for: 3, goals_against: 0, goal_difference: 3, points: 6
    )
    expect(group.standings.find { |r| r.team == d }).to have_attributes(
      position: 3, played: 0, won: 0, drawn: 0, lost: 0, points: 0, goal_difference: 0
    )
  end

  it "breaks goal-difference ties by goals for" do
    p = team("P")
    q = team("Q")
    r = team("R")
    group_match("C", p, r, home_score: 2, away_score: 0) # P: +2, GF 2
    group_match("C", q, r, home_score: 3, away_score: 1) # Q: +2, GF 3

    group = group_named(described_class.call(tournament: tournament), "C")

    # P and Q tie on points (3) and goal difference (+2); Q wins on goals for.
    expect(group.standings.map(&:team)).to eq([ q, p, r ])
  end

  it "counts a draw as one point each" do
    x = team("X")
    y = team("Y")
    group_match("D", x, y, home_score: 1, away_score: 1)

    group = group_named(described_class.call(tournament: tournament), "D")

    expect(group.standings).to all(have_attributes(played: 1, drawn: 1, won: 0, lost: 0, points: 1))
  end

  it "lists every team at zero for a group with no finished matches" do
    x = team("X")
    y = team("Y")
    z = team("Z")
    group_match("B", x, y)
    group_match("B", y, z)
    group_match("B", x, z)

    group = group_named(described_class.call(tournament: tournament), "B")

    expect(group.standings.map(&:team)).to contain_exactly(x, y, z)
    expect(group.standings).to all(have_attributes(
      played: 0, won: 0, drawn: 0, lost: 0,
      goals_for: 0, goals_against: 0, goal_difference: 0, points: 0
    ))
    expect(group.standings.map(&:position)).to contain_exactly(1, 2, 3)
  end

  it "returns one zeroed table per group when nothing has been played (A..L)" do
    ("A".."L").each do |g|
      group_match(g, team("#{g}1"), team("#{g}2"))
    end

    result = described_class.call(tournament: tournament)

    expect(result.map(&:name)).to eq(("A".."L").to_a) # ordered A..L
    expect(result.flat_map(&:standings)).to all(have_attributes(played: 0, points: 0))
  end

  it "ignores knockout matches and matches without a group" do
    a = team("A")
    b = team("B")
    create(:match, :round_of_16, :finished, tournament: tournament, home_team: a, away_team: b)
    group_match("A", a, b, home_score: 1, away_score: 0)

    group = group_named(described_class.call(tournament: tournament), "A")

    # Only the single group-stage match counts, not the knockout one.
    expect(group.standings.find { |r| r.team == a }.played).to eq(1)
  end

  it "is N+1-free regardless of match and team count" do
    4.times { |i| group_match("E", team("e#{i}h"), team("e#{i}a"), home_score: 1, away_score: 0) }
    6.times { |i| group_match("F", team("f#{i}h"), team("f#{i}a")) }

    query_count = 0
    counter = lambda do |_name, _started, _finished, _id, payload|
      query_count += 1 unless %w[SCHEMA TRANSACTION].include?(payload[:name])
    end

    ActiveSupport::Notifications.subscribed(counter, "sql.active_record") do
      described_class.call(tournament: tournament)
    end

    # Matches + the two team preloads (+ maybe a framework query); independent of counts.
    expect(query_count).to be <= 4
  end
end
