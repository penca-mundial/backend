# frozen_string_literal: true

require "rails_helper"

RSpec.describe PredictionScore, type: :model do
  it "has a valid factory" do
    expect(build(:prediction_score)).to be_valid
  end

  describe "associations" do
    it "reaches the user and match through the prediction" do
      score = create(:prediction_score)

      expect(score.user).to eq(score.prediction.user)
      expect(score.match).to eq(score.prediction.match)
    end
  end

  describe "validations" do
    it "rejects a non-positive multiplier" do
      expect(build(:prediction_score, multiplier: 0)).not_to be_valid
    end

    it "rejects negative component points" do
      expect(build(:prediction_score, points_result: -1)).not_to be_valid
    end

    it "rejects a second score for the same prediction" do
      score = create(:prediction_score)

      expect(build(:prediction_score, prediction: score.prediction)).not_to be_valid
    end
  end

  describe "#total_points" do
    it "scales the summed points by the multiplier on save" do
      score = create(:prediction_score, points_result: 5, points_advance: 3, multiplier: 1.5)

      expect(score.total_points).to eq(12) # (5 + 3) * 1.5
    end

    it "rounds the scaled total to the nearest integer" do
      score = create(:prediction_score, points_result: 3, points_advance: 0, multiplier: 1.5)

      expect(score.total_points).to eq(5) # 3 * 1.5 = 4.5 -> 5
    end

    it "recomputes when the components change" do
      score = create(:prediction_score, points_result: 1, points_advance: 0, multiplier: 1.0)

      score.update!(points_result: 4, multiplier: 2.0)

      expect(score.total_points).to eq(8) # 4 * 2.0
    end
  end
end
