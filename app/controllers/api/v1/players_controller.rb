# frozen_string_literal: true

module Api
  module V1
    # Public players index. Filterable by ?team_id= or ?tournament_id=; with no
    # filter it defaults to the current tournament (CurrentTournamentQuery).
    # Paginated (players can be a large collection — ~1200 for the World Cup).
    class PlayersController < BaseController
      skip_before_action :require_user!

      def index
        players = PlayersQuery.call(filters: player_filters)
        render_paginated(players, PlayerBlueprint)
      end

      private

      # Resolve exactly one scope, validating ids (unknown -> RecordNotFound ->
      # 404 via BaseController): an explicit team, else an explicit tournament,
      # else the current tournament.
      def player_filters
        return { team_id: Team.find(params[:team_id]).id } if params[:team_id].present?

        { tournament_id: resolved_tournament.id }
      end

      def resolved_tournament
        return Tournament.find(params[:tournament_id]) if params[:tournament_id].present?

        CurrentTournamentQuery.call || raise(ActiveRecord::RecordNotFound)
      end
    end
  end
end
