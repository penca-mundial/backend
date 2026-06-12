# frozen_string_literal: true

# Matches that MatchSyncJob should refresh on a given tick, in priority order:
#   1. every live match (polled each minute);
#   2. every "started" match — scheduled, but its kickoff has already passed and
#      the feed hasn't flipped it to live yet — polled each minute too, so we
#      catch the live transition the moment it lands;
#   3. up to MAX_UPCOMING_PER_TICK scheduled matches kicking off within
#      SCHEDULED_HORIZON that haven't been synced in SYNC_INTERVAL (or never).
# Everything else (finished, far-off, recently-synced) is left alone.
#
# Buckets 1 and 2 are never capped — they're the matches we most need fresh and
# there are only a handful at once. Bucket 3 is capped so a wave of soon-to-start
# fixtures going stale at the same instant can't burst the API rate limit and
# starve the live/started polls (SCRUM-313).
#
# Why "started" is its own, staleness-free bucket: with only the future-kickoff
# window below, a match that became stale AFTER its kickoff would never re-enter
# `now..(now + horizon)` and would be silently dropped forever — the dead-window
# deadlock where a scheduled 0-0 was never polled again and never went live.
class DueMatchSyncQuery < ApplicationQuery
  SCHEDULED_HORIZON = 24.hours
  SYNC_INTERVAL = 6.hours
  # Soft per-tick ceiling on bucket 3 only. Sized to leave headroom under the
  # client's 10 req/min free-tier limit for live + started polls and the other
  # sync jobs; overflow simply waits for the next minute's tick.
  MAX_UPCOMING_PER_TICK = 5

  def call
    base = relation || Match.all
    # Ordered by kickoff_at so live and started matches (kickoff in the past)
    # are synced before upcoming ones (kickoff in the future): if the rate limit
    # bites mid-tick, the matches that matter most have already gone through.
    base.where(id: due_ids(base)).order(:kickoff_at)
  end

  private

  def due_ids(base)
    (live_ids(base) + started_ids(base) + upcoming_stale_ids(base)).uniq
  end

  def live_ids(base)
    base.status_live.pluck(:id)
  end

  # Scheduled matches whose kickoff has passed but that haven't flipped to live
  # yet — polled every tick, no staleness gate. Bounded below by the horizon so a
  # genuinely stuck "zombie" (scheduled days after its kickoff) isn't polled
  # forever; anything that recent is a real match about to go live.
  def started_ids(base)
    now = Time.current
    base.status_scheduled.where(kickoff_at: (now - SCHEDULED_HORIZON)..now).pluck(:id)
  end

  # Future-kickoff scheduled matches due for a refresh, capped per tick and
  # ordered soonest-first so the matches closest to kickoff sync before the rest.
  def upcoming_stale_ids(base)
    now = Time.current
    upcoming = base.status_scheduled.where(kickoff_at: now..(now + SCHEDULED_HORIZON))
    upcoming.where(last_synced_at: nil)
            .or(upcoming.where(last_synced_at: ..(now - SYNC_INTERVAL)))
            .order(:kickoff_at)
            .limit(MAX_UPCOMING_PER_TICK)
            .pluck(:id)
  end
end
