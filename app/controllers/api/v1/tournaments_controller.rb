# frozen_string_literal: true

module Api
  module V1
    # Public tournament reads. Like MatchesController/StandingsController,
    # tournament data is public (no auth).
    class TournamentsController < BaseController
      skip_before_action :require_user!

      # GET /api/v1/tournaments/current — the canonical "current" tournament
      # (active -> upcoming -> most recent past). 404 only when none exist.
      def current
        tournament = CurrentTournamentQuery.call
        raise ActiveRecord::RecordNotFound if tournament.nil?

        render json: TournamentBlueprint.render_as_hash(tournament)
      end
    end
  end
end
