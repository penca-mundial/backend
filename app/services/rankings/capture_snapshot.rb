# frozen_string_literal: true

module Rankings
  # Persists a point-in-time leaderboard snapshot — one RankingSnapshot row per
  # user — for a tournament, either global (group: nil) or per-group.
  #
  # tournament is REQUIRED: ranking_snapshots.tournament_id is NOT NULL and the
  # snapshot is always intra-tournament. The caller (the recurring job / the
  # rankings controller) resolves the tournament and passes it; this service does
  # not reach for CurrentTournamentQuery.
  #
  #   group: nil  -> group_id NULL (global: every user)
  #   group: <g>  -> group_id = g.id (that group's members)
  #
  # Idempotent for a given snapshot_at: a bulk upsert keyed on the unique index
  # (user_id, group_id, tournament_id, snapshot_at) with NULLS NOT DISTINCT, so
  # re-running the SAME capture refreshes points/rank_position/exact_count (a late
  # scoring correction is picked up) without duplicating — including the global
  # case where group_id is NULL. upsert_all (not insert_all DO NOTHING) on purpose,
  # so a re-capture takes corrections.
  class CaptureSnapshot < Service
    # Columns refreshed on conflict. Verified behaviour: created_at is always
    # PRESERVED (omitted here so the SET never touches it), and updated_at IS
    # bumped automatically by upsert_all — which is exactly why it must NOT be
    # listed too (doing so raises "multiple assignments to same column").
    UPSERT_COLUMNS = %i[points rank_position exact_count].freeze

    def initialize(tournament:, group: nil, snapshot_at: Time.current)
      @tournament = tournament
      @group = group
      @snapshot_at = snapshot_at
    end

    def call
      entries = LeaderboardQuery.new.call(tournament: @tournament, group: @group, limit: nil)
      return success(count: 0) if entries.empty?

      rows = build_rows(entries)
      RankingSnapshot.upsert_all(
        rows,
        unique_by: :index_ranking_snapshots_unique_capture,
        update_only: UPSERT_COLUMNS
      )
      success(count: rows.size)
    end

    private

    def build_rows(entries)
      now = Time.current
      group_id = @group&.id
      entries.map do |entry|
        {
          user_id:       entry.user_id,
          group_id:      group_id,
          tournament_id: @tournament.id,
          snapshot_at:   @snapshot_at,
          points:        entry.points,
          rank_position: entry.rank_position,
          exact_count:   entry.exact_count,
          created_at:    now,
          updated_at:    now
        }
      end
    end
  end
end
