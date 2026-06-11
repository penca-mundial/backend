# frozen_string_literal: true

require "rails_helper"

RSpec.describe Scoring::MatchScoreCalculator do
  subject(:calculator) { described_class.new(match: match) }

  # In-memory match/prediction: the evaluator only reads attributes, so a live
  # (non-final) score works exactly like a final one.
  let(:match) { Match.new(phase: "group_stage", home_score: 1, away_score: 0) }

  before do
    create(:scoring_rule, rule_type: "exact_score", points: 5)
    create(:scoring_rule, rule_type: "correct_winner", points: 1)
  end

  describe "#total_for" do
    it "awards the exact-score points when the prediction nails the current score" do
      prediction = Prediction.new(predicted_home_score: 1, predicted_away_score: 0)

      expect(calculator.total_for(prediction)).to eq(5)
    end

    it "awards the correct-winner points when only the outcome matches" do
      prediction = Prediction.new(predicted_home_score: 3, predicted_away_score: 0)

      expect(calculator.total_for(prediction)).to eq(1)
    end

    it "awards zero when neither score, difference nor outcome matches" do
      prediction = Prediction.new(predicted_home_score: 0, predicted_away_score: 2)

      expect(calculator.total_for(prediction)).to eq(0)
    end

    it "scales by the phase multiplier (reusing PhaseMultiplier)" do
      create(:phase_multiplier, phase: "group_stage", multiplier: 2.0)
      prediction = Prediction.new(predicted_home_score: 1, predicted_away_score: 0)

      expect(calculator.total_for(prediction)).to eq(10)
    end
  end

  describe "#attributes_for" do
    it "returns the PredictionScore attribute shape with the classified rule" do
      prediction = Prediction.new(predicted_home_score: 1, predicted_away_score: 0)

      attrs = calculator.attributes_for(prediction)

      expect(attrs).to include(points_result: 5, points_advance: 0, multiplier: 1.0)
      expect(attrs[:breakdown]).to include(result_rule: :exact_score, multiplier_phase: "group_stage")
    end
  end
end
