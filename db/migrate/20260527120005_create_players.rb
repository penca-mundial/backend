# frozen_string_literal: true

class CreatePlayers < ActiveRecord::Migration[8.1]
  def change
    create_table :players do |t|
      t.references :team, null: false, foreign_key: true
      t.string :name,        null: false
      t.string :external_id

      t.timestamps
    end

    add_index :players, :external_id, unique: true

    # Tournament top scorer resolves to a player.
    add_foreign_key :tournaments, :players, column: :top_scorer_id
  end
end
