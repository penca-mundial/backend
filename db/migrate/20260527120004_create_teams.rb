# frozen_string_literal: true

class CreateTeams < ActiveRecord::Migration[8.1]
  def change
    create_table :teams do |t|
      t.references :tournament, null: false, foreign_key: true
      t.string :name,        null: false
      t.string :code3,       null: false, limit: 3
      t.string :flag_url
      t.string :external_id, null: false

      t.timestamps
    end

    add_index :teams, :external_id, unique: true
    add_index :teams, %i[tournament_id code3], unique: true

    # Tournament result references resolve to teams.
    add_foreign_key :tournaments, :teams, column: :champion_id
    add_foreign_key :tournaments, :teams, column: :runner_up_id
    add_foreign_key :tournaments, :teams, column: :third_place_id
    add_foreign_key :tournaments, :teams, column: :fourth_place_id
  end
end
