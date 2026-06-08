# frozen_string_literal: true

module Api
  module V1
    # Rankings (leaderboards). Authenticated. Thin: it gates on membership (group
    # variant only) and serializes LeaderboardQuery's rows. Both actions accept
    # ?window=total|today|week (delta windows — see LeaderboardQuery) and
    # ?page=/?per_page= pagination (default page size 25; the body carries
    # page/has_more). The historical snapshots / evolution endpoints are SCRUM-286.
    class RankingsController < BaseController
      MAX_LIMIT = 100
      WINDOWS = %w[total today week].freeze
      EVOLUTION_CACHE_TTL = 30.seconds

      # GET /api/v1/rankings/global — every user; no membership gate.
      def global
        render_leaderboard(current_tournament)
      end

      # GET /api/v1/rankings/groups/:id
      def group
        group = Group.find(params[:id])
        return render_forbidden unless member?(group)

        render_leaderboard(current_tournament, group: group)
      end

      # GET /api/v1/rankings/groups/:id/evolution — the per-penca multi-line
      # points/rank evolution chart (SCRUM-286). Authenticated + member-gated,
      # like #group. The line-set depends on current_user, so the short-TTL cache
      # key includes it.
      def group_evolution
        group = Group.find(params[:id])
        return render_forbidden unless member?(group)

        tournament = current_tournament
        body = Rails.cache.fetch(evolution_cache_key(group, tournament), expires_in: EVOLUTION_CACHE_TTL) do
          result = GroupEvolutionQuery.call(group: group, tournament: tournament, user: current_user)
          {
            available: result.available,
            lines:     GroupEvolutionLineBlueprint.render_as_hash(result.lines)
          }.to_json
        end
        render body: body, content_type: "application/json"
      end

      private

      def evolution_cache_key(group, tournament)
        "rankings:evolution:#{tournament.id}:#{group.id}:#{current_user.id}"
      end

      # Shared render path for both variants: one page of the ranked entries
      # (page/has_more let the SPA build "Ver más") plus the optional "me"
      # context window, which rides its own unpaginated path (position_of) and
      # is therefore identical on every page.
      def render_leaderboard(tournament, group: nil)
        result = LeaderboardQuery.new.page(
          tournament: tournament, group: group, window: window,
          number: page_number, per_page: per_page
        )
        me = if include_me?
               LeaderboardQuery.new.position_of(current_user, tournament: tournament, group: group, window: window)
        end

        render json: {
          entries:  RankingEntryBlueprint.render_as_hash(result.entries),
          me:       me && RankingEntryBlueprint.render_as_hash(me),
          page:     page_number,
          has_more: result.has_more
        }
      end

      # The leaderboard is scoped to the current tournament; pencas are
      # cross-tournament (no tournament_id), so it's resolved externally here.
      # 404 when there is no tournament at all.
      def current_tournament
        CurrentTournamentQuery.call || raise(ActiveRecord::RecordNotFound)
      end

      # 1-based; junk / non-positive input falls back to the first page.
      def page_number
        raw = params[:page].to_i
        raw.positive? ? raw : 1
      end

      # Page size: default 25 (LeaderboardQuery::PAGE_SIZE), capped at MAX_LIMIT
      # so callers can't inflate the cache key or ask for an absurd page.
      # ?limit= — the pre-pagination contract — is honored as a fallback so
      # existing clients keep their top-N until the frontend pagination
      # (SCRUM-280) lands.
      def per_page
        raw = (params[:per_page].presence || params[:limit]).to_i
        raw = LeaderboardQuery::PAGE_SIZE unless raw.positive?
        [ raw, MAX_LIMIT ].min
      end

      def include_me?
        ActiveModel::Type::Boolean.new.cast(params[:include_me])
      end

      # Known window or the cumulative default — mirrors per_page's forgiving
      # fallback instead of 400ing on junk input.
      def window
        raw = params[:window].to_s
        WINDOWS.include?(raw) ? raw.to_sym : :total
      end
    end
  end
end
