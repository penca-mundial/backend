# frozen_string_literal: true

# Matches that MatchSyncJob should refresh on a given tick:
#   * every live match (polled each minute), plus
#   * scheduled matches kicking off within SCHEDULED_HORIZON that haven't been
#     synced in the last SYNC_INTERVAL (or never).
# Everything else (finished, far-off, recently-synced) is left alone.
class DueMatchSyncQuery < ApplicationQuery
  SCHEDULED_HORIZON = 24.hours
  SYNC_INTERVAL = 6.hours

  def call
    base = relation || Match.all
    base.where(id: live_ids(base)).or(base.where(id: scheduled_stale_ids(base)))
  end

  private

  def live_ids(base)
    base.status_live.select(:id)
  end

  def scheduled_stale_ids(base)
    now = Time.current
    upcoming = base.status_scheduled.where(kickoff_at: now..(now + SCHEDULED_HORIZON))
    upcoming.where(last_synced_at: nil)
            .or(upcoming.where(last_synced_at: ..(now - SYNC_INTERVAL)))
            .select(:id)
  end
end
