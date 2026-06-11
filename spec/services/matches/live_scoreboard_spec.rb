# frozen_string_literal: true

require "rails_helper"

RSpec.describe Matches::LiveScoreboard do
  let(:user) { create(:user) }
  let(:tournament) { create(:tournament) }

  before { create(:scoring_rule, rule_type: "exact_score", points: 5) }

  def live_match(home:, away:)
    create(:match, :live, tournament: tournament, kickoff_at: 1.hour.ago,
                          home_score: home, away_score: away)
  end

  it "embeds the prediction and the projected points at the current live score" do
    match = live_match(home: 1, away: 0)
    create(:prediction, user: user, match: match, predicted_home_score: 1, predicted_away_score: 0)

    entry = described_class.call(matches: Match.where(id: match.id), user: user).data[:entries].first

    expect(entry[:my_prediction]).to include(predicted_home_score: 1, predicted_away_score: 0)
    expect(entry[:projected_points]).to eq(5) # exact match of the current score
  end

  it "nulls both fields when the user has no prediction for the match" do
    match = live_match(home: 0, away: 0)

    entry = described_class.call(matches: Match.where(id: match.id), user: user).data[:entries].first

    expect(entry[:my_prediction]).to be_nil
    expect(entry[:projected_points]).to be_nil
  end
end
