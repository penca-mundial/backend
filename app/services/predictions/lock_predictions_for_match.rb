# frozen_string_literal: true

module Predictions
  # Locks every still-open prediction for a match by stamping locked_at.
  # Called by MatchLockJob at kickoff. Idempotent: predictions that are already
  # locked are left untouched, so re-running never moves an existing lock time.
  # Returns a ServiceResult whose data is the number of rows locked.
  class LockPredictionsForMatch < Service
    def initialize(match:)
      @match = match
    end

    def call
      now = Time.current
      locked = Prediction.where(match_id: @match.id, locked_at: nil)
                         .update_all(locked_at: now, updated_at: now)
      success(locked)
    end
  end
end
