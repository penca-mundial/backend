# frozen_string_literal: true

class CreatePredictions < ActiveRecord::Migration[8.1]
  def change
    create_table :predictions do |t|
      # user_id is covered by the composite unique index below.
      t.references :user,  null: false, foreign_key: true, index: false
      t.references :match, null: false, foreign_key: true
      t.integer    :predicted_home_score, null: false
      t.integer    :predicted_away_score, null: false
      t.bigint     :predicted_advancing_team_id
      t.datetime   :locked_at

      t.timestamps
    end

    add_index :predictions, %i[user_id match_id], unique: true
    add_index :predictions, :predicted_advancing_team_id

    add_foreign_key :predictions, :teams, column: :predicted_advancing_team_id
  end
end
