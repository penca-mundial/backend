# frozen_string_literal: true

# Reads the full scoring configuration — the per-match/special rule points
# (ScoringRule) and the per-phase multipliers (PhaseMultiplier) — for the public
# rules page. Both come from the real, admin-editable tables, never from
# constants, so the API stays in sync when an admin changes a value at runtime.
#
# Rows are returned in the canonical enum order (ScoringRule::RULE_TYPES /
# PhaseMultiplier::PHASES) rather than by id, so the response order is stable and
# meaningful regardless of insertion order. A single SELECT per table — no N+1.
class ScoringConfigQuery < ApplicationQuery
  Config = Struct.new(:scoring_rules, :phase_multipliers, keyword_init: true)

  def call
    Config.new(
      scoring_rules:     ordered(ScoringRule.all, :rule_type, ScoringRule::RULE_TYPES),
      phase_multipliers: ordered(PhaseMultiplier.all, :phase, PhaseMultiplier::PHASES)
    )
  end

  private

  # Sort the loaded records by their enum's declared order. index_by loads the
  # relation once; the map preserves the canonical order and drops any enum
  # value without a row.
  def ordered(scope, attribute, order)
    by_value = scope.index_by { |record| record.public_send(attribute) }
    order.filter_map { |value| by_value[value] }
  end
end
