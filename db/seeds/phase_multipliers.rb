# frozen_string_literal: true

# Per-phase score multiplier, applied to (points_result + points_advance) on
# every PredictionScore. Defaults grow with the importance of the round; the
# third-place match stays at 1.0 to avoid inflating a marginal result.
module Seeds
  module PhaseMultipliers
    DEFAULTS = {
      group_stage:   1.0,
      round_of_32:   1.5,
      round_of_16:   2.0,
      quarter_final: 2.5,
      semi_final:    3.0,
      third_place:   3.5,
      final:         4.0
    }.freeze

    def self.call
      DEFAULTS.each do |phase, multiplier|
        ::PhaseMultiplier.find_or_create_by!(phase: phase) do |row|
          row.multiplier = multiplier
        end
      end
    end
  end
end
