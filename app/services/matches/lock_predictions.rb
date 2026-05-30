# frozen_string_literal: true

module Matches
  # Locks every still-open prediction for a match by stamping locked_at.
  # Idempotent: predictions that are already locked are left untouched, so
  # re-running never moves an existing lock time.
  class LockPredictions < Service
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
