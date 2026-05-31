# frozen_string_literal: true

class CreateStandings < ActiveRecord::Migration[8.1]
  def change
    create_table :standings do |t|
      t.references :tournament, null: false, foreign_key: true
      t.references :team, null: false, foreign_key: true
      # Group identifier as normalized from the upstream (e.g. "A".."L" for the
      # 2026 World Cup). Plain string with no length/value constraint so other
      # tournaments' group labels and counts work unchanged.
      t.string :group, null: false
      t.integer :position, null: false
      t.integer :played_games, null: false, default: 0
      t.integer :won, null: false, default: 0
      t.integer :draw, null: false, default: 0
      t.integer :lost, null: false, default: 0
      t.integer :goals_for, null: false, default: 0
      t.integer :goals_against, null: false, default: 0
      t.integer :goal_difference, null: false, default: 0
      t.integer :points, null: false, default: 0
      # Recent results string as returned by the API (e.g. "W,W,D,L"). Optional.
      t.string :form

      t.timestamps
    end

    add_index :standings, %i[tournament_id group]
    # One standings row per team per tournament.
    add_index :standings, %i[tournament_id team_id], unique: true
  end
end
