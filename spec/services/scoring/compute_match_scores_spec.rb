# frozen_string_literal: true

require "rails_helper"

RSpec.describe Scoring::ComputeMatchScores do
  # Don't assume seeds: create exactly the rules/multipliers under test.
  before do
    { exact_score: 10, correct_goal_difference: 6, correct_winner: 3, correct_advance: 5 }.each do |rule_type, points|
      ScoringRule.create!(rule_type: rule_type, points: points)
    end
    PhaseMultiplier.create!(phase: "group_stage", multiplier: 1.0)
    PhaseMultiplier.create!(phase: "round_of_16", multiplier: 2.0)
  end

  # Finished group-stage match, actual result 2-1.
  let(:match) { create(:match, :finished, home_score: 2, away_score: 1) }

  def score_for(prediction)
    prediction.reload.prediction_scores.first
  end

  describe "result dimension (group stage, multiplier 1.0, advance nil → 0)" do
    {
      [ 2, 1 ] => { rule: "exact_score",             points: 10 },
      [ 3, 2 ] => { rule: "correct_goal_difference", points: 6 },
      [ 3, 0 ] => { rule: "correct_winner",          points: 3 },
      [ 0, 1 ] => { rule: "no_match",                points: 0 }
    }.each do |(predicted_home, predicted_away), expected|
      it "scores #{expected[:rule]} → points_result #{expected[:points]}, total #{expected[:points]}" do
        prediction = create(:prediction, match: match,
                            predicted_home_score: predicted_home, predicted_away_score: predicted_away)

        result = described_class.call(match: match)

        expect(result).to be_success
        expect(result.data).to eq(count: 1)

        score = score_for(prediction)
        expect(score.points_result).to eq(expected[:points])
        expect(score.points_advance).to eq(0)
        expect(score.multiplier).to eq(1.0)
        expect(score.total_points).to eq(expected[:points]) # (points + 0) * 1.0
        expect(score.breakdown).to include("result_rule" => expected[:rule], "multiplier_phase" => "group_stage")
      end
    end
  end

  describe "knockout match (round_of_16, multiplier 2.0)" do
    let(:ko_match) do
      create(:match, :finished, :round_of_16, home_score: 2, away_score: 1).tap do |m|
        m.update!(advancing_team: m.home_team)
      end
    end

    it "adds advance points and applies the phase multiplier via the model callback" do
      prediction = create(:prediction, match: ko_match,
                          predicted_home_score: 2, predicted_away_score: 1,
                          predicted_advancing_team: ko_match.home_team) # exact + correct advance

      described_class.call(match: ko_match)

      score = score_for(prediction)
      expect(score.points_result).to eq(10)
      expect(score.points_advance).to eq(5)
      expect(score.multiplier).to eq(2.0)
      expect(score.total_points).to eq(30) # (10 + 5) * 2.0
      expect(score.breakdown).to include("advance_rule" => "correct_advance", "multiplier_phase" => "round_of_16")
    end

    it "gives no_advance 0 when the predicted advancing team is wrong" do
      prediction = create(:prediction, match: ko_match,
                          predicted_home_score: 2, predicted_away_score: 1,
                          predicted_advancing_team: ko_match.away_team)

      described_class.call(match: ko_match)

      score = score_for(prediction)
      expect(score.points_advance).to eq(0)
      expect(score.total_points).to eq(20) # (10 + 0) * 2.0
      expect(score.breakdown).to include("advance_rule" => "no_advance")
    end
  end

  describe "idempotency and recompute" do
    it "re-running does not duplicate scores and keeps the same values" do
      prediction = create(:prediction, match: match, predicted_home_score: 2, predicted_away_score: 1)

      described_class.call(match: match)
      expect { described_class.call(match: match) }.not_to change(PredictionScore, :count)

      expect(score_for(prediction).total_points).to eq(10)
    end

    it "updates the stored score when a ScoringRule changes and it is recomputed" do
      prediction = create(:prediction, match: match, predicted_home_score: 2, predicted_away_score: 1)
      described_class.call(match: match)
      expect(score_for(prediction).total_points).to eq(10)

      ScoringRule.find_by(rule_type: "exact_score").update!(points: 20)
      described_class.call(match: match)

      expect(score_for(prediction).total_points).to eq(20)
      expect(PredictionScore.count).to eq(1) # still no duplicate
    end
  end

  describe "concurrency and edge cases" do
    it "wraps the work in match.with_lock" do
      allow(match).to receive(:with_lock).and_call_original

      described_class.call(match: match)

      expect(match).to have_received(:with_lock)
    end

    it "returns count 0 and writes nothing for a match with no predictions" do
      result = described_class.call(match: match)

      expect(result.data).to eq(count: 0)
      expect(PredictionScore.count).to eq(0)
    end

    it "writes nothing and returns count 0 when the match is not finished" do
      scheduled = create(:match, kickoff_at: 1.week.from_now) # scheduled, scores default 0-0
      create(:prediction, match: scheduled, predicted_home_score: 2, predicted_away_score: 1)

      result = described_class.call(match: scheduled)

      expect(result).to be_success
      expect(result.data).to eq(count: 0)
      expect(PredictionScore.count).to eq(0)
    end
  end
end
