# frozen_string_literal: true

class AddBracketProgressionToMatches < ActiveRecord::Migration[8.1]
  def change
    change_table :matches do |t|
      # Self-referential FK: the next-round match this one's winner advances to.
      t.references :feeds_into_match, foreign_key: { to_table: :matches }
      # 0 = winner takes the home slot, 1 = away slot. Required when
      # feeds_into_match_id is set (enforced by a model validation).
      t.integer :feeds_into_slot
      # Ordinal position within the phase, used to draw the bracket left-to-right.
      t.integer :bracket_position
    end
  end
end
