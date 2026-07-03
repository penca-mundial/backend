# frozen_string_literal: true

require "rails_helper"

RSpec.describe FootballData::ReconcileFinishedMatch do
  def base = "https://api.football-data.org/v4"
  def json_headers = { "Content-Type" => "application/json" }

  def stub_match(external_id, score)
    stub_request(:get, "#{base}/matches/#{external_id}")
      .to_return(status: 200, body: { "score" => score }.to_json, headers: json_headers)
  end

  let(:tournament) { create(:tournament) }

  before do
    create(:scoring_rule, rule_type: "exact_score", points: 10)
    create(:scoring_rule, rule_type: "correct_advance", points: 5)
    create(:phase_multiplier, phase: "round_of_32", multiplier: 1.5)
  end

  # Prod incident (match #84 POR 2-2 CRO): a Croatia goal was disallowed after the close,
  # so the real result is 2-1 Portugal, but we froze on the draw. The settled feed shows 2-1.
  it "corrects a stale 90' score from the settled feed and re-scores" do
    match = create(:match, :round_of_32, :finished, tournament: tournament, external_id: "rec-por",
                                                     home_score: 2, away_score: 2)
    match.update_column(:advancing_team_id, match.home_team_id)
    pred = create(:prediction, user: create(:user), match: match,
                               predicted_home_score: 2, predicted_away_score: 2,
                               predicted_advancing_team_id: match.home_team_id)
    Scoring::ComputeMatchScores.call(match: match) # scored against the wrong 2-2 (exact + advance)
    expect(pred.prediction_scores.first.reload.total_points).to eq(23) # (10 + 5) * 1.5 -> 22.5 -> 23

    stub_match("rec-por", "winner" => "HOME_TEAM", "duration" => "REGULAR",
                          "fullTime" => { "home" => 2, "away" => 1 })

    result = described_class.call(match: match)

    expect(result.data[:changed]).to be(true)
    expect(match.reload).to have_attributes(home_score: 2, away_score: 1)
    # Re-scored against 2-1: the 2-2 pick is no longer exact; only the advance remains.
    expect(pred.prediction_scores.first.reload.total_points).to eq(8) # (0 + 5) * 1.5 -> 7.5 -> 8
  end

  it "corrects a stale advancing team from the settled shootout feed (keeps the 90' score)" do
    match = create(:match, :round_of_32, :finished, tournament: tournament, external_id: "rec-adv",
                                                     home_score: 1, away_score: 1)
    match.update_column(:advancing_team_id, match.home_team_id) # frozen wrong
    stub_match("rec-adv", "winner" => nil, "duration" => "PENALTY_SHOOTOUT",
                          "regularTime" => { "home" => 1, "away" => 1 },
                          "fullTime" => { "home" => 3, "away" => 4 })

    described_class.call(match: match)

    expect(match.reload).to have_attributes(home_score: 1, away_score: 1, advancing_team_id: match.away_team_id)
  end

  it "is a no-op when the feed agrees with what we stored" do
    match = create(:match, :round_of_32, :finished, tournament: tournament, external_id: "rec-ok",
                                                     home_score: 2, away_score: 1)
    match.update_column(:advancing_team_id, match.home_team_id)
    stub_match("rec-ok", "winner" => "HOME_TEAM", "fullTime" => { "home" => 2, "away" => 1 })

    result = described_class.call(match: match)

    expect(result.data[:changed]).to be(false)
  end

  it "never overrides a manually-pinned result and does not even read the feed" do
    match = create(:match, :round_of_32, :finished, tournament: tournament, external_id: "rec-man",
                                                     home_score: 5, away_score: 0, manual_override: true)

    result = described_class.call(match: match)

    expect(result.data[:changed]).to be(false)
    expect(a_request(:get, "#{base}/matches/rec-man")).not_to have_been_made
  end

  it "does nothing for a match that is not finished" do
    match = create(:match, :round_of_32, :live, tournament: tournament, external_id: "rec-live",
                                                 home_score: 1, away_score: 0)

    result = described_class.call(match: match)

    expect(result.data[:changed]).to be(false)
    expect(a_request(:get, "#{base}/matches/rec-live")).not_to have_been_made
  end

  it "corrects only the score for a group-stage match, never an advancing team" do
    match = create(:match, :finished, tournament: tournament, external_id: "rec-grp",
                                      home_score: 1, away_score: 1) # group_stage
    stub_match("rec-grp", "winner" => "HOME_TEAM", "fullTime" => { "home" => 2, "away" => 1 })

    described_class.call(match: match)

    expect(match.reload).to have_attributes(home_score: 2, away_score: 1, advancing_team_id: nil)
  end
end
