# frozen_string_literal: true

# Filters the fixture for Api::V1::MatchesController#index. Every filter is
# optional; absent filters are skipped. team_id matches either side of the tie.
class MatchesQuery < ApplicationQuery
  def initialize(relation = Match.all, filters: {})
    super(relation)
    @filters = filters
  end

  def call
    scope = relation || Match.all
    scope = scope.where(phase: @filters[:phase]) if @filters[:phase].present?
    scope = scope.where(status: @filters[:status]) if @filters[:status].present?
    scope = scope.where(kickoff_at: parse(@filters[:date_from])..) if @filters[:date_from].present?
    scope = scope.where(kickoff_at: ..parse(@filters[:date_to])) if @filters[:date_to].present?
    scope = by_team(scope, @filters[:team_id]) if @filters[:team_id].present?
    scope
  end

  private

  def by_team(scope, team_id)
    scope.where(home_team_id: team_id).or(scope.where(away_team_id: team_id))
  end

  def parse(value)
    Time.zone.parse(value.to_s)
  end
end
