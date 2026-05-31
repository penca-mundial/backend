# frozen_string_literal: true

# Standings for one tournament, preloaded and ordered for the grouped serializer
# (group ascending, then position ascending within each group). Preloads :team
# so StandingBlueprint doesn't trigger an N+1.
class StandingsQuery < ApplicationQuery
  def initialize(tournament:, relation: nil)
    super(relation)
    @tournament = tournament
  end

  def call
    (relation || Standing.all)
      .where(tournament: @tournament)
      .includes(:team)
      .ordered
  end
end
