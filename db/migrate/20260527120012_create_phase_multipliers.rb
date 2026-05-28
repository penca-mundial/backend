# frozen_string_literal: true

class CreatePhaseMultipliers < ActiveRecord::Migration[8.1]
  def change
    create_table :phase_multipliers do |t|
      t.string  :phase, null: false
      t.decimal :multiplier, precision: 4, scale: 2, null: false, default: "1.00"

      t.timestamps
    end

    add_index :phase_multipliers, :phase, unique: true
  end
end
