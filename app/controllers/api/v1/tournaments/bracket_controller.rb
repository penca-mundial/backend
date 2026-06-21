# frozen_string_literal: true

module Api
  module V1
    module Tournaments
      # GET /api/v1/tournaments/:id/bracket — the knockout bracket, data-driven
      # (SCRUM-316/317). Public, mirroring the rest of the fixture reads; a
      # signed-in viewer additionally gets their own pick embedded per match
      # (my_prediction), hard-gated to locked picks inside Brackets::ListBracket.
      #
      # Anonymous responses (no per-user data) are cached briefly — shorter while
      # anything is live — to absorb polling; signed-in responses are per-user and
      # never share that cache (mirrors MatchesController#live).
      class BracketController < BaseController
        skip_before_action :require_user!

        def index
          tournament = Tournament.find(params[:id])

          return render json: payload(tournament, current_user) if current_user

          body = Rails.cache.fetch(cache_key(tournament), expires_in: cache_ttl) { payload(tournament, nil).to_json }
          render body: body, content_type: "application/json"
        end

        private

        def payload(tournament, viewer)
          { matches: Brackets::ListBracket.call(tournament: tournament, viewer: viewer).data[:matches] }
        end

        def cache_key(tournament)
          "tournament:#{tournament.id}:bracket"
        end

        def cache_ttl
          Match.status_live.exists? ? 10.seconds : 5.minutes
        end
      end
    end
  end
end
