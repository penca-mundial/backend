# frozen_string_literal: true

module Api
  module V1
    # Public fixture endpoints. Auth is skipped, but #show enriches the payload
    # with the current user's prediction when one is signed in. Responses are
    # cached briefly (shorter while matches are live) to absorb traffic spikes.
    class MatchesController < BaseController
      skip_before_action :require_user!

      def index
        matches = MatchesQuery.call(filters: filter_params).includes(:home_team, :away_team)
        render_paginated(matches, MatchBlueprint)
      end

      def show
        match = Match.includes(:home_team, :away_team).find(params[:id])
        payload = cached("match:#{match.id}:#{match.updated_at.to_i}") { MatchBlueprint.render_as_hash(match) }
        payload = payload.merge(my_prediction: my_prediction_hash(match)) if current_user
        render json: payload
      end

      def live
        matches = Match.status_live.includes(:home_team, :away_team).order(:kickoff_at)
        render body: cached("matches:live") { MatchBlueprint.render(matches) }, content_type: "application/json"
      end

      def today
        window = today_window(params[:tz])
        matches = Match.where(kickoff_at: window).includes(:home_team, :away_team).order(:kickoff_at)
        render body: cached("matches:today:#{window.begin.to_i}") { MatchBlueprint.render(matches) },
               content_type: "application/json"
      end

      private

      def filter_params
        params.permit(:phase, :status, :date_from, :date_to, :team_id).to_h.symbolize_keys
      end

      # Short TTL while anything is live (scores change fast), longer otherwise.
      def cached(key, &)
        Rails.cache.fetch(key, expires_in: Match.status_live.exists? ? 10.seconds : 5.minutes, &)
      end

      def today_window(timezone)
        zone = ActiveSupport::TimeZone[timezone.to_s] || ActiveSupport::TimeZone["UTC"]
        zone.now.beginning_of_day..zone.now.end_of_day
      end

      def my_prediction_hash(match)
        prediction = current_user.predictions.find_by(match_id: match.id)
        prediction && PredictionBlueprint.render_as_hash(prediction)
      end
    end
  end
end
