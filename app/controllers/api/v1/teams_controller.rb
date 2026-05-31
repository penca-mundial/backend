# frozen_string_literal: true

module Api
  module V1
    # Public teams index, scoped to a tournament via ?tournament_id= (defaults to
    # the current tournament via CurrentTournamentQuery). Ordered by name. Small
    # collection, so no pagination (follows the standings convention).
    class TeamsController < BaseController
      skip_before_action :require_user!

      def index
        teams = TeamsQuery.call(tournament: resolved_tournament)
        render body: TeamBlueprint.render(teams, view: :extended), content_type: "application/json"
      end

      private

      # Param-scoped when given, else the canonical current tournament. 404 (via
      # BaseController's RecordNotFound handler) when the id is unknown or there
      # is no tournament at all.
      def resolved_tournament
        return Tournament.find(params[:tournament_id]) if params[:tournament_id].present?

        CurrentTournamentQuery.call || raise(ActiveRecord::RecordNotFound)
      end
    end
  end
end
