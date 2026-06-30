# frozen_string_literal: true

# Delayed re-resolution of a penalty-shootout knockout's advancing team. SyncMatch
# enqueues this at staggered offsets after a knockout finishes level on 90', so we
# converge on the real winner once the football-data feed has settled (the finishing
# read is unreliable for shootouts). Thin: it invokes the reconciliation service.
class ShootoutReconcileJob < ApplicationJob
  queue_as :sync

  # A deleted match won't come back, so there is nothing to reconcile.
  discard_on ActiveRecord::RecordNotFound

  def perform(match_id)
    FootballData::ReconcileShootoutAdvance.call(match: Match.find(match_id))
  end
end
