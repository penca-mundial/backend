# frozen_string_literal: true

require "rails_helper"

RSpec.describe Scoring::MatchRuleEvaluator do
  # Pure function — build in-memory records, no DB.
  def evaluate(predicted:, actual:, phase: "group_stage",
               predicted_advancing_team_id: nil, advancing_team_id: nil)
    match = Match.new(phase: phase, home_score: actual[0], away_score: actual[1],
                      advancing_team_id: advancing_team_id)
    prediction = Prediction.new(predicted_home_score: predicted[0],
                                predicted_away_score: predicted[1],
                                predicted_advancing_team_id: predicted_advancing_team_id)
    described_class.call(prediction: prediction, match: match)
  end

  # One representative scoreline per result rule (exclusive, highest applicable):
  #   exact_score             — predicted == actual
  #   correct_goal_difference — same difference, not exact
  #   correct_winner          — same outcome, different difference
  #   no_match                — different outcome
  results = {
    exact_score:             { predicted: [ 2, 1 ], actual: [ 2, 1 ] },
    correct_goal_difference: { predicted: [ 3, 2 ], actual: [ 2, 1 ] },
    correct_winner:          { predicted: [ 1, 0 ], actual: [ 3, 1 ] },
    no_match:                { predicted: [ 0, 1 ], actual: [ 2, 1 ] }
  }.freeze

  describe "group-stage matches (advance_rule is nil)" do
    results.each do |expected, scores|
      it "classifies #{expected} with a nil advance_rule" do
        result = evaluate(**scores, phase: "group_stage")

        expect(result).to be_success
        expect(result.data).to eq(result_rule: expected, advance_rule: nil)
      end
    end
  end

  describe "knockout matches where the advancing team is correct" do
    results.each do |expected, scores|
      it "classifies #{expected} with correct_advance" do
        result = evaluate(**scores, phase: "round_of_16",
                          predicted_advancing_team_id: 10, advancing_team_id: 10)

        expect(result.data).to eq(result_rule: expected, advance_rule: :correct_advance)
      end
    end
  end

  describe "knockout matches where the advancing team is wrong" do
    results.each do |expected, scores|
      it "classifies #{expected} with no_advance" do
        result = evaluate(**scores, phase: "round_of_16",
                          predicted_advancing_team_id: 20, advancing_team_id: 10)

        expect(result.data).to eq(result_rule: expected, advance_rule: :no_advance)
      end
    end
  end
end
