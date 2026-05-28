# frozen_string_literal: true

class CreateTournaments < ActiveRecord::Migration[8.1]
  def change
    create_table :tournaments do |t|
      t.string   :name,      null: false
      t.datetime :starts_at, null: false
      t.datetime :ends_at,   null: false

      # Result columns. Foreign keys are added once teams/players exist
      # (see CreateTeams and CreatePlayers).
      t.bigint :champion_id
      t.bigint :runner_up_id
      t.bigint :third_place_id
      t.bigint :fourth_place_id
      t.bigint :top_scorer_id

      t.timestamps
    end

    add_index :tournaments, :champion_id
    add_index :tournaments, :runner_up_id
    add_index :tournaments, :third_place_id
    add_index :tournaments, :fourth_place_id
    add_index :tournaments, :top_scorer_id
  end
end
