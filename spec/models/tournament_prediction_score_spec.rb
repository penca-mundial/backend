# frozen_string_literal: true

require "rails_helper"

RSpec.describe TournamentPredictionScore, type: :model do
  it "has a valid factory" do
    expect(build(:tournament_prediction_score)).to be_valid
  end

  describe "associations" do
    it "reaches the user through the tournament prediction" do
      score = create(:tournament_prediction_score)

      expect(score.user).to eq(score.tournament_prediction.user)
    end
  end

  describe "validations" do
    it "rejects negative component points" do
      expect(build(:tournament_prediction_score, points_champion: -1)).not_to be_valid
    end

    it "rejects a second score for the same tournament prediction" do
      score = create(:tournament_prediction_score)

      expect(
        build(:tournament_prediction_score, tournament_prediction: score.tournament_prediction)
      ).not_to be_valid
    end
  end

  describe "#total_points" do
    it "sums the five component scores on save" do
      score = create(
        :tournament_prediction_score,
        points_champion: 10,
        points_runner_up: 5,
        points_third: 3,
        points_fourth: 2,
        points_top_scorer: 7
      )

      expect(score.total_points).to eq(27)
    end

    it "recomputes when a component changes" do
      score = create(:tournament_prediction_score, points_champion: 1)

      score.update!(points_champion: 4)

      expect(score.total_points).to eq(4)
    end
  end
end
