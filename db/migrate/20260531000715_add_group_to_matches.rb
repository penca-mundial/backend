# frozen_string_literal: true

class AddGroupToMatches < ActiveRecord::Migration[8.1]
  def change
    # Group-stage identifier (e.g. "A".."L" for the 2026 World Cup). Nullable:
    # knockout matches belong to no group. Stored as the upstream returns it
    # post-normalization — not constrained to A-L — so other tournaments work.
    add_column :matches, :group, :string

    # Supports the Grupos tab / standings queries scoped to a tournament.
    add_index :matches, %i[tournament_id group]
  end
end
