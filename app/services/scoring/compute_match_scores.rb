# frozen_string_literal: true

module Scoring
  # Computes and persists a PredictionScore for every prediction of a FINISHED
  # match. Classification is delegated to MatchRuleEvaluator (SCRUM-135); this
  # service maps the rule symbols to points via ScoringRule / PhaseMultiplier
  # and upserts the score rows.
  #
  # Idempotent: re-running on the same match upserts by prediction_id (no
  # duplicates) and re-reads the rule/multiplier tables, so changing a
  # ScoringRule and recomputing updates the stored scores.
  #
  # Returns a ServiceResult with { count: <predictions scored> }.
  class ComputeMatchScores < Service
    def initialize(match:)
      @match = match
    end

    def call
      # Guard: scoring a non-finished match would read its 0-0 default scores
      # and persist garbage. The caller (the scoring job) only enqueues on the
      # finished transition, but we enforce it here too.
      unless @match.status_finished?
        log_info("ComputeMatchScores skipped: match ##{@match.id} is not finished (#{@match.status})")
        return success(count: 0)
      end

      count = 0
      @match.with_lock do
        @match.predictions.each do |prediction|
          score_prediction(prediction)
          count += 1
        end
      end

      success(count: count)
    end

    private

    def score_prediction(prediction)
      eval_result = invoke { MatchRuleEvaluator.call(prediction: prediction, match: @match) }
      result_rule = eval_result[:result_rule]
      advance_rule = eval_result[:advance_rule]

      score = PredictionScore.find_or_initialize_by(prediction_id: prediction.id)
      score.points_result  = points_for(result_rule)
      score.points_advance = advance_rule ? points_for(advance_rule) : 0
      score.multiplier     = multiplier_for(@match.phase)
      score.breakdown      = { result_rule:, advance_rule:, multiplier_phase: @match.phase }
      score.computed_at    = Time.current
      # total_points is derived by PredictionScore's before_save callback.
      score.save!
    end

    # ScoringRule.for returns the points integer (or nil for the sentinel rules
    # :no_match / :no_advance, which have no row) — never hardcode points here.
    def points_for(rule)
      ScoringRule.for(rule) || 0
    end

    # PhaseMultiplier.for returns the multiplier as a Float (or nil when the
    # phase is unconfigured) — never hardcode the multiplier here.
    def multiplier_for(phase)
      PhaseMultiplier.for(phase) || 1.0
    end
  end
end
