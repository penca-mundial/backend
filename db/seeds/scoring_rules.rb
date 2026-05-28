# frozen_string_literal: true

# Default point values for each rule type. Admins can adjust them at runtime;
# this only seeds the rows so the table is non-empty out of the gate.
module Seeds
  module ScoringRules
    DEFAULTS = {
      exact_score:             10,
      correct_goal_difference: 6,
      correct_winner:          3,
      correct_advance:         5,
      champion_correct:        50,
      runner_up_correct:       30,
      third_place_correct:     20,
      fourth_place_correct:    10,
      top_scorer_correct:      25
    }.freeze

    def self.call
      DEFAULTS.each do |rule_type, points|
        ::ScoringRule.find_or_create_by!(rule_type: rule_type) do |rule|
          rule.points = points
        end
      end
    end
  end
end
