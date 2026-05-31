# frozen_string_literal: true

# Teams for one tournament, ordered by name. Returns a chainable relation
# (mirrors StandingsQuery).
class TeamsQuery < ApplicationQuery
  def initialize(tournament:, relation: nil)
    super(relation)
    @tournament = tournament
  end

  def call
    (relation || Team.all).where(tournament: @tournament).order(:name)
  end
end
