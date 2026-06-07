# frozen_string_literal: true

module Api
  module V1
    module Tournaments
      # GET /api/v1/tournaments/:id/standings/projected — the group-stage
      # tables PROJECTED for the authenticated user: official finished results
      # blended with current_user's predictions for the matches not played yet
      # (ProjectedGroupStandingsQuery, ADR 0005). Same response shape as the
      # official sibling endpoint (GroupStandingBlueprint), which stays public
      # and untouched.
      #
      # Authenticated (no skip of require_user!): the projection is personal by
      # definition. Not cached: the body is per-user, so the sibling's shared
      # 30s TTL doesn't apply, and rendering costs only two queries (matches +
      # the user's predictions).
      class ProjectedStandingsController < BaseController
        def index
          tournament = Tournament.find(params[:id])
          groups = ProjectedGroupStandingsQuery.call(tournament: tournament, user: current_user)
          render json: GroupStandingBlueprint.render(groups)
        end
      end
    end
  end
end
