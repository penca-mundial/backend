# frozen_string_literal: true

module Api
  module V1
    # Rankings (leaderboards). Authenticated. Thin: it gates on membership (group
    # variant only) and serializes LeaderboardQuery's rows. Both actions accept
    # ?window=total|today|week (delta windows — see LeaderboardQuery). The
    # historical snapshots / evolution endpoints are SCRUM-286.
    class RankingsController < BaseController
      MAX_LIMIT = 100
      DEFAULT_LIMIT = 100
      WINDOWS = %w[total today week].freeze

      # GET /api/v1/rankings/global — every user; no membership gate.
      def global
        tournament = current_tournament
        entries = LeaderboardQuery.new.call(tournament: tournament, window: window, limit: limit)
        me = if include_me?
               LeaderboardQuery.new.position_of(current_user, tournament: tournament, window: window)
        end

        render json: {
          entries: RankingEntryBlueprint.render_as_hash(entries),
          me:      me && RankingEntryBlueprint.render_as_hash(me)
        }
      end

      # GET /api/v1/rankings/groups/:id
      def group
        group = Group.find(params[:id])
        return render_forbidden unless member?(group)

        tournament = current_tournament
        entries = LeaderboardQuery.new.call(tournament: tournament, group: group, limit: limit, window: window)
        me = if include_me?
               LeaderboardQuery.new.position_of(current_user, tournament: tournament, group: group, window: window)
        end

        render json: {
          entries: RankingEntryBlueprint.render_as_hash(entries),
          me:      me && RankingEntryBlueprint.render_as_hash(me)
        }
      end

      private

      # The leaderboard is scoped to the current tournament; pencas are
      # cross-tournament (no tournament_id), so it's resolved externally here.
      # 404 when there is no tournament at all.
      def current_tournament
        CurrentTournamentQuery.call || raise(ActiveRecord::RecordNotFound)
      end

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

      # Known window or the cumulative default — mirrors limit's forgiving
      # fallback instead of 400ing on junk input.
      def window
        raw = params[:window].to_s
        WINDOWS.include?(raw) ? raw.to_sym : :total
      end
    end
  end
end
