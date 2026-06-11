# frozen_string_literal: true

module Api
  module V1
    # Public fixture endpoints. Auth is skipped, but #show enriches the payload
    # with the current user's prediction when one is signed in. Responses are
    # cached briefly (shorter while matches are live) to absorb traffic spikes.
    class MatchesController < BaseController
      skip_before_action :require_user!

      RECENT_FINISHED_LIMIT = 3

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
        # Signed-in users get a per-user payload (prediction + live points), so it
        # can't share the public cache; everyone else gets the cached, user-
        # agnostic fixture.
        return render json: user_scoreboard(matches) if current_user

        render body: cached("matches:live") { MatchBlueprint.render(matches) }, content_type: "application/json"
      end

      def today
        window = today_window(params[:tz])
        matches = Match.where(kickoff_at: window).includes(:home_team, :away_team).order(:kickoff_at)
        render body: cached("matches:today:#{window.begin.to_i}") { MatchBlueprint.render(matches) },
               content_type: "application/json"
      end

      # The soonest scheduled match still ahead of now (for the Home countdown);
      # null when the fixture has no upcoming match.
      def next_match
        match = Match.status_scheduled.where(kickoff_at: Time.current..)
                     .includes(:home_team, :away_team).order(:kickoff_at).first
        render json: match && MatchBlueprint.render_as_hash(match)
      end

      # The current tournament's most recent finished matches (up to 3, newest
      # first) for the Home recap. For a signed-in user each match embeds a
      # compact my_prediction with the points it scored against the FINAL result
      # (computed on the fly, per match); anonymous callers get the plain fixture.
      def recent_finished
        matches = Match.status_finished.where(tournament: current_tournament)
                       .includes(:home_team, :away_team).order(kickoff_at: :desc).limit(RECENT_FINISHED_LIMIT)
        return render json: user_scoreboard(matches) if current_user

        render json: MatchBlueprint.render_as_hash(matches)
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

      def user_scoreboard(matches)
        Matches::UserScoreboard.call(matches: matches, user: current_user).data[:entries]
      end

      # The tournament whose recap we show; nil-safe (no tournament -> no matches).
      def current_tournament
        @current_tournament ||= CurrentTournamentQuery.call
      end
    end
  end
end
