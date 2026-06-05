# frozen_string_literal: true

module Api
  module V1
    # Rankings (leaderboards). Authenticated. Thin: it gates on membership and
    # serializes LeaderboardQuery's rows. This is the canonical Phase 7 path;
    # SCRUM-155 adds global/snapshots/evolution actions to this same controller.
    class RankingsController < BaseController
      MAX_LIMIT = 100
      DEFAULT_LIMIT = 100

      # GET /api/v1/rankings/groups/:id
      def group
        group = Group.find(params[:id])
        return render_forbidden unless member?(group)

        entries = LeaderboardQuery.new.call(group: group, limit: limit)
        me = include_me? ? LeaderboardQuery.new.position_of(current_user, group: group) : nil

        render json: {
          entries: RankingEntryBlueprint.render_as_hash(entries),
          me:      me && RankingEntryBlueprint.render_as_hash(me)
        }
      end

      private

      # Positive, capped at MAX_LIMIT so callers can't inflate the cache key or
      # ask for an absurd page. Non-numeric / non-positive falls back to default.
      def limit
        raw = params[:limit].to_i
        raw = DEFAULT_LIMIT unless raw.positive?
        [ raw, MAX_LIMIT ].min
      end

      def include_me?
        ActiveModel::Type::Boolean.new.cast(params[:include_me])
      end
    end
  end
end
