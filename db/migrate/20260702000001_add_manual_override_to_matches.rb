# frozen_string_literal: true

# ADR-0007: a boolean that pins a hand-verified result so the recurring score
# reconciliation won't revert it to a (still-wrong) feed value. Additive, defaulting
# to false — existing rows need no backfill.
class AddManualOverrideToMatches < ActiveRecord::Migration[8.1]
  def change
    add_column :matches, :manual_override, :boolean, null: false, default: false
  end
end
