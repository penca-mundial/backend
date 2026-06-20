# frozen_string_literal: true

module Api
  module V1
    # Public profile of any user, visible to any authenticated viewer.
    #
    #   GET /api/v1/users/:id/profile     — ranking + shared-penca standings +
    #                                       tournament prediction (gated) + stats.
    #   GET /api/v1/users/:id/predictions — the target's LOCKED match picks
    #                                       (finished + live), paginated.
    #
    # The service account is not a real user and is never shown (404). The lock /
    # reveal gating is enforced server-side inside the services and queries — the
    # controller only intakes params and serializes the prepared payload.
    class UserProfilesController < BaseController
      def show
        result = Profiles::BuildProfile.call(
          viewer: current_user, target: target, tournament: current_tournament
        )
        render json: result.data
      end

      def predictions
        result = Profiles::ListLockedPredictions.call(
          target: target, tournament: current_tournament,
          page: page_number, per_page: per_page
        )
        render json: result.data
      end

      private

      def target
        @target ||= User.find(params[:id]).tap do |user|
          raise ActiveRecord::RecordNotFound if user.system?
        end
      end

      def current_tournament
        CurrentTournamentQuery.call || raise(ActiveRecord::RecordNotFound)
      end

      def page_number
        raw = params[:page].to_i
        raw.positive? ? raw : 1
      end

      def per_page
        raw = params[:per_page].to_i
        raw = LockedMatchPredictionsQuery::DEFAULT_PER_PAGE unless raw.positive?
        [ raw, LockedMatchPredictionsQuery::MAX_PER_PAGE ].min
      end
    end
  end
end
