# frozen_string_literal: true

class AddMinuteToMatches < ActiveRecord::Migration[8.1]
  def change
    # Current minute of play for live matches (and the final minute on finish),
    # as reported by football-data.org. Nullable: scheduled matches have no
    # minute. Display-only (never queried), so no index.
    add_column :matches, :minute, :integer
  end
end
