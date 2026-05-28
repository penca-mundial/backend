# frozen_string_literal: true

class CreateRankingSnapshots < ActiveRecord::Migration[8.1]
  def change
    create_table :ranking_snapshots do |t|
      # user_id leads the (user_id, snapshot_at) index below, so no standalone one.
      t.references :user,  null: false, foreign_key: true, index: false
      t.references :group, foreign_key: true
      t.integer  :points,        null: false
      t.integer  :rank_position, null: false
      t.datetime :snapshot_at,   null: false

      t.timestamps
    end

    # Leaderboard reads: rows for a snapshot within a (global or group) scope,
    # already ordered by rank.
    add_index :ranking_snapshots, %i[snapshot_at group_id rank_position],
              name: "index_ranking_snapshots_on_snapshot_group_rank"
    # A single user's history.
    add_index :ranking_snapshots, %i[user_id snapshot_at]
  end
end
