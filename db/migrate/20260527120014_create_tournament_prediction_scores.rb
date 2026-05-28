# frozen_string_literal: true

class CreateTournamentPredictionScores < ActiveRecord::Migration[8.1]
  def change
    create_table :tournament_prediction_scores do |t|
      t.references :tournament_prediction,
                   null: false, foreign_key: true, index: { unique: true }
      t.integer  :points_champion,   null: false, default: 0
      t.integer  :points_runner_up,  null: false, default: 0
      t.integer  :points_third,      null: false, default: 0
      t.integer  :points_fourth,     null: false, default: 0
      t.integer  :points_top_scorer, null: false, default: 0
      t.integer  :total_points,      null: false, default: 0
      t.datetime :computed_at, null: false

      t.timestamps
    end
  end
end
