# frozen_string_literal: true

class CreatePredictionScores < ActiveRecord::Migration[8.1]
  def change
    create_table :prediction_scores do |t|
      t.references :prediction, null: false, foreign_key: true, index: { unique: true }
      t.integer  :points_result,  null: false, default: 0
      t.integer  :points_advance, null: false, default: 0
      t.decimal  :multiplier, precision: 4, scale: 2, null: false, default: "1.00"
      t.integer  :total_points,   null: false, default: 0
      t.jsonb    :breakdown, null: false, default: {}
      t.datetime :computed_at, null: false

      t.timestamps
    end

    add_index :prediction_scores, :computed_at
  end
end
