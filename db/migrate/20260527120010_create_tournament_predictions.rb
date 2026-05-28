# frozen_string_literal: true

class CreateTournamentPredictions < ActiveRecord::Migration[8.1]
  def change
    create_table :tournament_predictions do |t|
      # user_id is covered by the composite unique index below.
      t.references :user,       null: false, foreign_key: true, index: false
      t.references :tournament, null: false, foreign_key: true
      t.bigint :champion_id
      t.bigint :runner_up_id
      t.bigint :third_place_id
      t.bigint :fourth_place_id
      t.bigint :top_scorer_id
      t.datetime :locked_at

      t.timestamps
    end

    add_index :tournament_predictions, %i[user_id tournament_id], unique: true
    add_index :tournament_predictions, :champion_id
    add_index :tournament_predictions, :runner_up_id
    add_index :tournament_predictions, :third_place_id
    add_index :tournament_predictions, :fourth_place_id
    add_index :tournament_predictions, :top_scorer_id

    add_foreign_key :tournament_predictions, :teams, column: :champion_id
    add_foreign_key :tournament_predictions, :teams, column: :runner_up_id
    add_foreign_key :tournament_predictions, :teams, column: :third_place_id
    add_foreign_key :tournament_predictions, :teams, column: :fourth_place_id
    add_foreign_key :tournament_predictions, :players, column: :top_scorer_id
  end
end
