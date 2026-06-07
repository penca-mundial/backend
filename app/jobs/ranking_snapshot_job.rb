# frozen_string_literal: true

# Captures the GLOBAL ranking snapshot for the current tournament once a day's
# matches have all finished. Chained from MatchScoringJob after each scored
# match: every call but the day's last one no-ops via the "still-pending matches"
# guard.
#
# Only the global snapshot is captured (group: nil). Per-group evolution/history
# is derived from the global rows at query time — points are absolute and
# group-independent — so this runs ONE LeaderboardQuery per capture, not one per
# group (see the ticket's own simpler-approach note; SCRUM-153 Option A).
class RankingSnapshotJob < ApplicationJob
  queue_as :default

  # date_iso lets the caller pin the UTC day of the match it just scored, so the
  # decision is robust across the midnight boundary. Defaults to "today" in UTC.
  def perform(date_iso = nil)
    tournament = CurrentTournamentQuery.call
    return unless tournament

    day = date_iso ? Date.iso8601(date_iso) : Time.now.utc.to_date
    # NOT day.beginning_of_day.utc: that anchors midnight in the SYSTEM zone and
    # then converts, shifting snapshot_at/window on any non-UTC host. to_time(:utc)
    # is midnight UTC of the date regardless of system TZ.
    day_start = day.to_time(:utc)

    # Not the last finished match of the day yet → wait for a later trigger.
    return if pending_matches?(tournament, day_start)

    # snapshot_at normalized to the UTC day: a re-score of the day's last match
    # re-runs this and upserts the SAME rows (idempotent via CaptureSnapshot's
    # unique index), instead of writing a new set each time.
    Rankings::CaptureSnapshot.call(tournament: tournament, snapshot_at: day_start)
  end

  private

  # Any scheduled/live match of this tournament kicking off within the UTC day?
  # (postponed/cancelled never "finish", so they don't block the capture.)
  def pending_matches?(tournament, day_start)
    tournament.matches
              .where(status: %w[scheduled live])
              .where(kickoff_at: day_start...(day_start + 1.day))
              .exists?
  end
end
