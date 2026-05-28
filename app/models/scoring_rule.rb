# frozen_string_literal: true

class ScoringRule < ApplicationRecord
  RULE_TYPES = %w[
    exact_score correct_goal_difference correct_winner correct_advance
    champion_correct runner_up_correct third_place_correct fourth_place_correct
    top_scorer_correct
  ].freeze

  enum :rule_type, RULE_TYPES.index_with(&:itself)

  validates :rule_type, presence: true, uniqueness: true
  validates :points, numericality: { only_integer: true, greater_than_or_equal_to: 0 }

  # Points awarded for the given rule type, or nil when unconfigured.
  def self.for(rule_type)
    find_by(rule_type: rule_type)&.points
  end
end
