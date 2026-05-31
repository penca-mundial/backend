# frozen_string_literal: true

class AddExternalCodeToTournaments < ActiveRecord::Migration[8.1]
  def change
    # football-data.org competition code for this tournament (e.g. "WC", "CL",
    # "EC"). Per-tournament so standings/fixtures sync is parameterized rather
    # than hardcoded to a single competition. Nullable: a tournament may exist
    # before its upstream code is known; sync skips tournaments without one.
    add_column :tournaments, :external_code, :string
    add_index :tournaments, :external_code
  end
end
