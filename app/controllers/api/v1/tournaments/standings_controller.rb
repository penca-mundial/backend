# frozen_string_literal: true

module Api
  module V1
    module Tournaments
      # GET /api/v1/tournaments/:id/standings — the CALCULATED group-stage tables
      # (composition from Match#group, stats from finished results). Public on
      # purpose: it mirrors the auth policy of the GET /api/v1/standings feed
      # (SCRUM-262) it will replace, so the front-end swap is transparent. All
      # computation lives in GroupStandingsQuery; this controller only resolves
      # the tournament, calls the query, serializes.
      #
      # Cached with a short TTL (rather than invalidating on each finished match):
      # standings only move when a group match ends, so ~30s of staleness is
      # irrelevant, and the TTL simply dedupes the SPA's polling. Distinct from
      # the mirrored GET /api/v1/standings (SCRUM-262), which is untouched.
      class StandingsController < BaseController
        skip_before_action :require_user!

        CACHE_TTL = 30.seconds

        def index
          tournament = Tournament.find(params[:id])
          body = Rails.cache.fetch(cache_key(tournament), expires_in: CACHE_TTL) do
            GroupStandingBlueprint.render(GroupStandingsQuery.call(tournament: tournament))
          end
          render body: body, content_type: "application/json"
        end

        private

        def cache_key(tournament)
          "tournament:#{tournament.id}:group_standings"
        end
      end
    end
  end
end
