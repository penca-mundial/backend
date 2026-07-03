# frozen_string_literal: true

require "rails_helper"

RSpec.describe MatchReconcileJob do
  def base = "https://api.football-data.org/v4"
  def json_headers = { "Content-Type" => "application/json" }

  it "reconciles the match, correcting a stale score from the settled feed" do
    create(:scoring_rule, rule_type: "exact_score", points: 10)
    match = create(:match, :round_of_32, :finished, external_id: "job-rec",
                                                     home_score: 2, away_score: 2)
    match.update_column(:advancing_team_id, match.home_team_id)
    stub_request(:get, "#{base}/matches/job-rec").to_return(
      status: 200, headers: json_headers,
      body: { "score" => { "winner" => "HOME_TEAM", "fullTime" => { "home" => 2, "away" => 1 } } }.to_json
    )

    described_class.perform_now(match.id)

    expect(match.reload).to have_attributes(home_score: 2, away_score: 1)
  end

  it "discards without raising when the match no longer exists" do
    expect { described_class.perform_now(-1) }.not_to raise_error
  end
end
