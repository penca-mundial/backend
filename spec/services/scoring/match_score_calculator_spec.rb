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

  # SCRUM-312: the advance component is projected only when the user picked who
  # advances. The result component is unaffected throughout.
  describe "knockout advance component" do
    before { create(:scoring_rule, rule_type: "correct_advance", points: 3) }

    # A LIVE knockout: the match has not defined an advancing team yet (nil).
    let(:live_ko) do
      Match.new(phase: "round_of_16", home_score: 1, away_score: 0,
                home_team_id: 10, away_team_id: 20, advancing_team_id: nil)
    end

    context "when the user did NOT predict who advances (no pick)" do
      subject(:attrs) { described_class.new(match: live_ko).attributes_for(prediction) }

      let(:prediction) do
        Prediction.new(predicted_home_score: 1, predicted_away_score: 0, predicted_advancing_team_id: nil)
      end

      it "awards no advance points (no phantom correct_advance against an undefined advance)" do
        expect(attrs[:points_advance]).to eq(0)
      end

      it "marks the advance rule nil (component absent, like the group stage)" do
        expect(attrs[:breakdown][:advance_rule]).to be_nil
      end

      it "still projects the result component normally" do
        expect(attrs[:points_result]).to eq(5) # 1-0 exact vs the current live score
      end
    end

    context "when the user predicted who advances but the match has not decided yet (live)" do
      it "keeps the advance component but awards 0 (no_advance), not a phantom" do
        prediction = Prediction.new(predicted_home_score: 1, predicted_away_score: 0,
                                    predicted_advancing_team_id: 10)

        attrs = described_class.new(match: live_ko).attributes_for(prediction)

        expect(attrs[:points_advance]).to eq(0)
        expect(attrs[:breakdown][:advance_rule]).to eq(:no_advance)
      end
    end

    context "when the user predicted the team the match marks as advancing (finished)" do
      it "awards the correct-advance points (unchanged from today)" do
        finished_ko = Match.new(phase: "round_of_16", home_score: 2, away_score: 1,
                                home_team_id: 10, away_team_id: 20, advancing_team_id: 10)
        prediction = Prediction.new(predicted_home_score: 2, predicted_away_score: 1,
                                    predicted_advancing_team_id: 10)

        attrs = described_class.new(match: finished_ko).attributes_for(prediction)

        expect(attrs[:points_advance]).to eq(3)
        expect(attrs[:breakdown][:advance_rule]).to eq(:correct_advance)
      end
    end

    context "when the user predicted the wrong advancing team (finished)" do
      it "awards no advance points (no_advance)" do
        finished_ko = Match.new(phase: "round_of_16", home_score: 2, away_score: 1,
                                home_team_id: 10, away_team_id: 20, advancing_team_id: 10)
        prediction = Prediction.new(predicted_home_score: 2, predicted_away_score: 1,
                                    predicted_advancing_team_id: 20)

        attrs = described_class.new(match: finished_ko).attributes_for(prediction)

        expect(attrs[:points_advance]).to eq(0)
        expect(attrs[:breakdown][:advance_rule]).to eq(:no_advance)
      end
    end
  end
end
