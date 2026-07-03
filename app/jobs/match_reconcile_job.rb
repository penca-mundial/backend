# frozen_string_literal: true

# Delayed score/advancing reconciliation for a finished match (ADR-0007). SyncMatch
# enqueues this at staggered offsets when a match finishes, so we re-read it once the
# feed has settled and correct a stale result — a shootout winner the feed reported
# late, or a score changed after the close (disallowed goal, VAR reversal, late data
# fix). Event-driven: nothing runs unless a match actually finished. Thin: it invokes
# the reconciliation service, which is idempotent and respects manual_override.
class MatchReconcileJob < ApplicationJob
  queue_as :sync

  # A deleted match won't come back, so there is nothing to reconcile.
  discard_on ActiveRecord::RecordNotFound

  def perform(match_id)
    FootballData::ReconcileFinishedMatch.call(match: Match.find(match_id))
  end
end
