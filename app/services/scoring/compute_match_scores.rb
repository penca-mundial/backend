# frozen_string_literal: true

module Scoring
  # Computes and persists a PredictionScore for every prediction of a FINISHED
  # match. Classification is delegated to MatchRuleEvaluator (SCRUM-135); this
  # service maps the rule symbols to points via ScoringRule / PhaseMultiplier
  # and upserts one score row per prediction.
  #
  # Concurrency: there is no coarse lock. Safety rests on the unique index on
  # prediction_id — each row is upserted independently, and a lost double-insert
  # race is rescued and retried as an update. Because the computed attributes are
  # deterministic for a given (prediction, match, rules), the racing writers
  # converge on the same row and values without duplicating.
  #
  # Idempotent: re-running re-reads the rule/multiplier tables, so changing a
  # ScoringRule and recomputing updates the stored scores.
  #
  # Returns a ServiceResult with { count: <predictions scored> }.
  class ComputeMatchScores < Service
    def initialize(match:)
      @match = match
      @points_cache = {}
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
      # find_each keeps memory bounded for large fields; order is irrelevant.
      @match.predictions.find_each do |prediction|
        upsert_score(prediction)
        count += 1
      end

      success(count: count)
    end

    private

    # Idempotent, concurrency-safe upsert keyed by the unique prediction_id.
    # Evaluate once, build the attributes once, and reuse them on the retry so
    # the racing writers converge.
    def upsert_score(prediction)
      attributes = score_attributes(prediction)

      write_score(prediction.id, attributes)
    rescue ActiveRecord::RecordNotUnique
      # Lost a double-insert race: the row exists now. Re-find and write the same
      # deterministic attributes — converges without a duplicate.
      PredictionScore.find_by!(prediction_id: prediction.id).update!(attributes)
    end

    def write_score(prediction_id, attributes)
      score = PredictionScore.find_or_initialize_by(prediction_id: prediction_id)
      score.assign_attributes(attributes)
      # total_points is derived by PredictionScore's before_save callback.
      score.save!
    end

    def score_attributes(prediction)
      eval_data = invoke { MatchRuleEvaluator.call(prediction: prediction, match: @match) }
      result_rule = eval_data[:result_rule]
      advance_rule = eval_data[:advance_rule]

      {
        points_result:  points_for(result_rule),
        points_advance: advance_rule ? points_for(advance_rule) : 0,
        multiplier:     multiplier,
        breakdown:      { result_rule:, advance_rule:, multiplier_phase: @match.phase },
        computed_at:    Time.current
      }
    end

    # Constant across the run; memoized so per-row save! query-cache clears don't
    # cause repeat lookups.
    def multiplier
      @multiplier ||= PhaseMultiplier.for(@match.phase) || 1.0
    end

    # Data-driven, memoized per rule. Sentinels (:no_match / :no_advance / nil)
    # have no ScoringRule row → 0. key? guards so a memoized 0 isn't re-queried.
    def points_for(rule)
      return @points_cache[rule] if @points_cache.key?(rule)

      @points_cache[rule] = ScoringRule.for(rule) || 0
    end
  end
end
