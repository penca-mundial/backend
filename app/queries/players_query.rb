# frozen_string_literal: true

# Filters players for Api::V1::PlayersController#index. Filters are optional and
# applied when present (mirrors MatchesQuery). Tournament scoping goes through
# the player's team via a subquery, so the result stays a single-table relation
# that preloads :team cleanly (no join/includes interaction).
class PlayersQuery < ApplicationQuery
  def initialize(relation = Player.all, filters: {})
    super(relation)
    @filters = filters
  end

  def call
    scope = relation || Player.all
    scope = scope.where(team_id: @filters[:team_id]) if @filters[:team_id].present?
    scope = by_tournament(scope, @filters[:tournament_id]) if @filters[:tournament_id].present?
    # :id is a tie-breaker so the order is total — without it, equal names give
    # an undefined order and LIMIT/OFFSET pagination can drop or repeat rows
    # across page boundaries.
    scope.includes(:team).order(:name, :id)
  end

  private

  def by_tournament(scope, tournament_id)
    scope.where(team_id: Team.where(tournament_id: tournament_id).select(:id))
  end
end
