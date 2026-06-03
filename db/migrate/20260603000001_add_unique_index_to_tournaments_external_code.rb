# frozen_string_literal: true

# Enforce the "one tournament per external_code" invariant at the DB level
# (SCRUM-274). Partial so multiple rows may keep a nil external_code; only the
# non-null competition codes (e.g. "WC") must be unique.
class AddUniqueIndexToTournamentsExternalCode < ActiveRecord::Migration[8.0]
  def change
    remove_index :tournaments, :external_code, name: "index_tournaments_on_external_code"
    add_index :tournaments, :external_code, unique: true,
              where: "external_code IS NOT NULL",
              name: "index_tournaments_on_external_code"
  end
end
