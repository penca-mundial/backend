# frozen_string_literal: true

# Augments the existing ranking_snapshots table (created empty in SCRUM-99) for
# the Phase 7 snapshot sub-feature. Additive ALTER — the table has no rows and no
# consumers yet, so NOT NULL needs no backfill.
class AugmentRankingSnapshotsForPhase7 < ActiveRecord::Migration[8.1]
  def change
    # Multi-tournament: a snapshot always belongs to a tournament, even the global
    # (group_id NULL) one — "everyone in THIS tournament", never cross-tournament.
    # No standalone index: the composite read index below leads with tournament_id.
    add_reference :ranking_snapshots, :tournament, null: false, foreign_key: true, index: false
    add_column :ranking_snapshots, :exact_count, :integer, null: false, default: 0

    # Idempotency for CaptureSnapshot. NULLS NOT DISTINCT (PG 15+; we run 16) so the
    # global case (group_id NULL) can't insert duplicate rows — without it NULL
    # group_ids would each be "distinct" and the unique constraint wouldn't hold.
    add_index :ranking_snapshots, %i[user_id group_id tournament_id snapshot_at],
              unique: true, nulls_not_distinct: true,
              name: "index_ranking_snapshots_unique_capture"

    # Read path: a tournament's window (group or global) ordered by rank.
    add_index :ranking_snapshots, %i[tournament_id group_id snapshot_at rank_position],
              name: "index_ranking_snapshots_on_tournament_group_snapshot_rank"

    # Drop the indexes now subsumed by the composites above. column: is given so
    # the migration reverses cleanly (the rollback recreates them).
    remove_index :ranking_snapshots, column: :group_id,
                 name: "index_ranking_snapshots_on_group_id"
    remove_index :ranking_snapshots, column: %i[snapshot_at group_id rank_position],
                 name: "index_ranking_snapshots_on_snapshot_group_rank"
  end
end
