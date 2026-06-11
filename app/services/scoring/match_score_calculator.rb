# frozen_string_literal: true

module Scoring
  # Pure-fabrication calculator that maps one prediction, against a match's
  # CURRENT score, to PredictionScore attributes (and the resulting total). It is
  # the single home of the "rule symbols -> points -> total" mapping, reused by
  # two callers:
  #
  #   * ComputeMatchScores — persists a PredictionScore per prediction of a
  #     finished match (the real, stored scoring).
  #   * Matches::UserScoreboard — the points a prediction scores against a match's
  #     CURRENT score (live or final), computed read-only and never persisted.
  #
  # Classification is delegated to MatchRuleEvaluator (the actual rules); the
  # configured values come from ScoringRule / PhaseMultiplier; the total is
  # derived by PredictionScore itself (#computed_total_points) so the formula is
  # never re-implemented here. It NEVER touches the database for writes and never
  # reads the match score from the DB — it compares whatever score the given
  # match instance carries, so a live (non-final) score works unchanged.
  #
  # The rule-points and per-phase multiplier lookups are memoized; pass shared
  # caches to reuse them across many matches (e.g. one live scoreboard) so the
  # config reads stay constant rather than scaling with the match count.
  class MatchScoreCalculator
    def initialize(match:, points_cache: {}, multiplier_cache: {})
      @match = match
      @points_cache = points_cache
      @multiplier_cache = multiplier_cache
    end

    # The PredictionScore attribute hash for this prediction against the match's
    # current score. The caller adds persistence-only fields (computed_at) when
    # it writes a row; the projected path never persists, so they are omitted.
    def attributes_for(prediction)
      eval_data = MatchRuleEvaluator.call(prediction: prediction, match: @match).data
      result_rule = eval_data[:result_rule]
      advance_rule = eval_data[:advance_rule]

      {
        points_result:  points_for(result_rule),
        points_advance: advance_rule ? points_for(advance_rule) : 0,
        multiplier:     multiplier,
        breakdown:      { result_rule:, advance_rule:, multiplier_phase: @match.phase }
      }
    end

    # The points this prediction earns at the match's current score, derived by
    # the PredictionScore model's own formula (no persistence, no duplication).
    def total_for(prediction)
      PredictionScore.new(attributes_for(prediction)).computed_total_points
    end

    private

    # Constant for a given phase; memoized (shared across matches when a cache is
    # injected). Unconfigured phase -> 1.0 (no scaling).
    def multiplier
      @multiplier_cache[@match.phase] ||= (PhaseMultiplier.for(@match.phase) || 1.0)
    end

    # Data-driven, memoized per rule. Sentinels (:no_match / :no_advance / nil)
    # have no ScoringRule row -> 0. key? guards so a memoized 0 isn't re-queried.
    def points_for(rule)
      return @points_cache[rule] if @points_cache.key?(rule)

      @points_cache[rule] = ScoringRule.for(rule) || 0
    end
  end
end
