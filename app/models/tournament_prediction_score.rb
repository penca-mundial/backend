# frozen_string_literal: true

class TournamentPredictionScore < ApplicationRecord
  COMPONENT_SCORES = %i[
    points_champion points_runner_up points_third points_fourth points_top_scorer
  ].freeze

  belongs_to :tournament_prediction
  has_one :user, through: :tournament_prediction

  validates :tournament_prediction_id, uniqueness: true
  validates(*COMPONENT_SCORES,
            numericality: { only_integer: true, greater_than_or_equal_to: 0 })
  validates :computed_at, presence: true

  before_save :compute_total_points

  private

  # total_points is the sum of the five podium/top-scorer component scores,
  # stored on the row so leaderboard RANK() queries hit a real column.
  def compute_total_points
    self.total_points = COMPONENT_SCORES.sum { |attr| public_send(attr) }
  end
end
