# frozen_string_literal: true

require "rails_helper"

RSpec.describe Matches::UserScoreboard do
  let(:user) { create(:user) }
  let(:tournament) { create(:tournament) }

  before { create(:scoring_rule, rule_type: "exact_score", points: 5) }

  it "embeds a compact prediction with points scored against the match's current score" do
    match = create(:match, :live, tournament: tournament, kickoff_at: 1.hour.ago,
                                  home_score: 1, away_score: 0)
    create(:prediction, user: user, match: match, predicted_home_score: 1, predicted_away_score: 0)

    entry = described_class.call(matches: Match.where(id: match.id), user: user).data[:entries].first

    expect(entry[:my_prediction]).to eq(predicted_home_score: 1, predicted_away_score: 0, points: 5)
  end

  it "computes points on the fly from the calculator, not from a stored PredictionScore" do
    match = create(:match, :finished, tournament: tournament, kickoff_at: 1.day.ago,
                                      home_score: 2, away_score: 1)
    prediction = create(:prediction, user: user, match: match,
                                     predicted_home_score: 2, predicted_away_score: 1)
    # A stale/misleading stored score the service must IGNORE.
    create(:prediction_score, prediction: prediction, points_result: 999, multiplier: 1.0)

    entry = described_class.call(matches: Match.where(id: match.id), user: user).data[:entries].first

    expect(entry[:my_prediction][:points]).to eq(5) # exact vs the 2-1 final, not the stored 999
  end

  it "nulls my_prediction when the user has no prediction for the match" do
    match = create(:match, :finished, tournament: tournament, kickoff_at: 1.day.ago,
                                      home_score: 0, away_score: 0)

    entry = described_class.call(matches: Match.where(id: match.id), user: user).data[:entries].first

    expect(entry[:my_prediction]).to be_nil
  end
end
