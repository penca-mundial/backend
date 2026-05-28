# frozen_string_literal: true

class CreateMatches < ActiveRecord::Migration[8.1]
  def change
    create_table :matches do |t|
      t.references :tournament, null: false, foreign_key: true
      t.bigint   :home_team_id,        null: false
      t.bigint   :away_team_id,        null: false
      t.bigint   :advancing_team_id
      t.datetime :kickoff_at,          null: false
      t.datetime :original_kickoff_at, null: false
      t.string   :status,              null: false, default: "scheduled"
      t.string   :phase,               null: false
      t.integer  :home_score,          null: false, default: 0
      t.integer  :away_score,          null: false, default: 0
      t.jsonb    :events_log,          null: false, default: []
      t.string   :external_id,         null: false

      t.timestamps
    end

    add_index :matches, :external_id, unique: true
    add_index :matches, :kickoff_at
    add_index :matches, :status
    add_index :matches, %i[tournament_id phase]
    add_index :matches, :home_team_id
    add_index :matches, :away_team_id
    add_index :matches, :advancing_team_id

    add_foreign_key :matches, :teams, column: :home_team_id
    add_foreign_key :matches, :teams, column: :away_team_id
    add_foreign_key :matches, :teams, column: :advancing_team_id

    add_check_constraint :matches, "home_team_id <> away_team_id",
                         name: "matches_home_and_away_differ"
  end
end
