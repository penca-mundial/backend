# frozen_string_literal: true

class PredictionScore < ApplicationRecord
  belongs_to :prediction
  has_one :user,  through: :prediction
  has_one :match, through: :prediction

  validates :prediction_id, uniqueness: true
  validates :points_result, :points_advance,
            numericality: { only_integer: true, greater_than_or_equal_to: 0 }
  validates :multiplier, numericality: { greater_than: 0 }
  validates :computed_at, presence: true

  before_save :compute_total_points

  # The raw match points scaled by the phase multiplier and rounded to the
  # nearest integer. Pure and side-effect-free, so a "what-if" projection (e.g.
  # the points a prediction would earn at a live match's current score) can reuse
  # the exact stored-scoring formula on an unsaved record without persisting it.
  def computed_total_points
    ((points_result + points_advance) * multiplier).round
  end

  private

  # total_points is stored on the row (not derived on read) so leaderboard
  # RANK() queries hit a real, indexable column.
  def compute_total_points
    self.total_points = computed_total_points
  end
end
