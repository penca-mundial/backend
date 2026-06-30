# frozen_string_literal: true

require "rails_helper"

RSpec.describe FootballData::ReconcileShootoutAdvance do
  def base = "https://api.football-data.org/v4"
  def json_headers = { "Content-Type" => "application/json" }

  def stub_match(external_id, score)
    stub_request(:get, "#{base}/matches/#{external_id}")
      .to_return(status: 200, body: { "score" => score }.to_json, headers: json_headers)
  end

  let(:tournament) { create(:tournament) }

  before do
    create(:scoring_rule, rule_type: "correct_advance", points: 5)
    create(:scoring_rule, rule_type: "correct_goal_difference", points: 6)
    create(:phase_multiplier, phase: "round_of_32", multiplier: 1.5)
  end

  # Reproduces the prod incident (match #75 NED 1-1 MAR): the finishing read froze the
  # advancing team on the home side, but the settled feed shows the away side won on
  # penalties. The reconciliation must flip advancing and re-score.
  it "corrects a frozen advancing team from the settled feed and re-scores" do
    match = create(:match, :round_of_32, :finished, tournament: tournament, external_id: "rec-1",
                                                     home_score: 1, away_score: 1,
                                                     advancing_team_id: nil)
    match.update_column(:advancing_team_id, match.home_team_id) # frozen wrong
    # 2-2 is a draw matching the 1-1 goal difference (not the exact score).
    pred = create(:prediction, user: create(:user), match: match,
                               predicted_home_score: 2, predicted_away_score: 2,
                               predicted_advancing_team_id: match.home_team_id)
    create(:prediction_score, prediction: pred, points_result: 6, points_advance: 5, multiplier: 1.5)

    # Settled feed: winner still nil, but fullTime gives the away team.
    stub_match("rec-1", "winner" => nil, "duration" => "PENALTY_SHOOTOUT",
                        "regularTime" => { "home" => 1, "away" => 1 },
                        "penalties" => { "home" => 3, "away" => 3 },
                        "fullTime" => { "home" => 3, "away" => 4 })

    result = described_class.call(match: match)

    expect(result).to be_success
    expect(result.data[:changed]).to be(true)
    expect(match.reload.advancing_team_id).to eq(match.away_team_id)
    # Re-scored: the home-advance pick now loses the advance component (goal diff only).
    expect(pred.prediction_scores.first.reload).to have_attributes(points_advance: 0, total_points: 9)
  end

  it "resolves from the winner field when the feed has populated it" do
    match = create(:match, :round_of_32, :finished, tournament: tournament, external_id: "rec-win",
                                                     home_score: 2, away_score: 2)
    match.update_column(:advancing_team_id, match.home_team_id)
    stub_match("rec-win", "winner" => "AWAY_TEAM", "fullTime" => { "home" => 2, "away" => 2 })

    described_class.call(match: match)

    expect(match.reload.advancing_team_id).to eq(match.away_team_id)
  end

  it "is a no-op when the stored advancing already matches the settled feed" do
    match = create(:match, :round_of_32, :finished, tournament: tournament, external_id: "rec-ok",
                                                     home_score: 1, away_score: 1)
    match.update_column(:advancing_team_id, match.away_team_id)
    stub_match("rec-ok", "winner" => nil, "fullTime" => { "home" => 3, "away" => 4 })

    expect do
      result = described_class.call(match: match)
      expect(result.data[:changed]).to be(false)
    end.not_to change { match.reload.advancing_team_id }
  end

  it "leaves the match untouched when the feed has not settled into a decisive result" do
    match = create(:match, :round_of_32, :finished, tournament: tournament, external_id: "rec-tied",
                                                     home_score: 1, away_score: 1)
    match.update_column(:advancing_team_id, match.home_team_id)
    stub_match("rec-tied", "winner" => nil, "fullTime" => { "home" => 1, "away" => 1 })

    expect do
      described_class.call(match: match)
    end.not_to change { match.reload.advancing_team_id }
  end

  it "does nothing for a knockout settled in 90' (not a shootout)" do
    match = create(:match, :round_of_32, :finished, tournament: tournament, external_id: "rec-90",
                                                     home_score: 2, away_score: 0)
    match.update_column(:advancing_team_id, match.home_team_id)

    result = described_class.call(match: match)

    expect(result.data[:changed]).to be(false)
    expect(a_request(:get, "#{base}/matches/rec-90")).not_to have_been_made
  end

  it "does nothing for a group-stage match" do
    match = create(:match, :finished, tournament: tournament, external_id: "rec-grp",
                                      home_score: 1, away_score: 1)

    result = described_class.call(match: match)

    expect(result.data[:changed]).to be(false)
    expect(a_request(:get, "#{base}/matches/rec-grp")).not_to have_been_made
  end
end
