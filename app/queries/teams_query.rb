# frozen_string_literal: true

# Teams PARTICIPATING in one tournament (those playing a match of its fixture,
# not merely tagged with its tournament_id — seed leftovers stay out), ordered
# by name. Returns a chainable relation (mirrors StandingsQuery).
class TeamsQuery < ApplicationQuery
  def initialize(tournament:, relation: nil)
    super(relation)
    @tournament = tournament
  end

  def call
    (relation || Team.all).where(id: @tournament.participating_team_ids).order(:name)
  end
end
