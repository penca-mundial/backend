# frozen_string_literal: true

module Api
  module V1
    # Public group-standings endpoint. Scoped to a tournament via ?tournament_id=
    # (defaults to the sole/first tournament when omitted, matching the rest of
    # the public read API). Returns standings grouped by group letter, ordered by
    # position within each group:
    #   { "groups": { "A": [ {position, team, points, ...}, ... ], "B": [...] } }
    class StandingsController < BaseController
      skip_before_action :require_user!

      def index
        standings = StandingsQuery.call(tournament: resolved_tournament)
        render json: { groups: StandingBlueprint.grouped(standings) }
      end

      private

      def resolved_tournament
        return Tournament.find(params[:tournament_id]) if params[:tournament_id].present?

        CurrentTournamentQuery.call || raise(ActiveRecord::RecordNotFound)
      end
    end
  end
end
