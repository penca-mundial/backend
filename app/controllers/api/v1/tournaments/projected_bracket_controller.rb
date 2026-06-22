# frozen_string_literal: true

module Api
  module V1
    module Tournaments
      # GET /api/v1/tournaments/:id/bracket/projected — the Round-of-32 projected
      # for the authenticated user (their group predictions blended with real
      # results), so the SPA can draw "según tus pronósticos" before the real
      # bracket is confirmed (SCRUM-319). Authenticated by definition (the
      # projection is personal) — no skip of require_user!; anonymous callers get
      # the real, data-faithful bracket from the public /bracket endpoint instead.
      class ProjectedBracketController < BaseController
        def index
          tournament = Tournament.find(params[:id])
          render json: Brackets::ProjectBracket.call(tournament: tournament, user: current_user).data
        end
      end
    end
  end
end
