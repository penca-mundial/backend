# frozen_string_literal: true

class CreateScoringRules < ActiveRecord::Migration[8.1]
  def change
    create_table :scoring_rules do |t|
      t.string  :rule_type, null: false
      t.integer :points,    null: false, default: 0

      t.timestamps
    end

    add_index :scoring_rules, :rule_type, unique: true
  end
end
