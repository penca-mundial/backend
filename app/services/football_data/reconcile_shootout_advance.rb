# frozen_string_literal: true

module FootballData
  # Re-resolves the advancing team of a finished knockout that went to a shootout,
  # from a fresh feed read, and re-scores when it changed.
  #
  # Why this exists: at the instant a penalty match is marked finished, football-data's
  # result is not yet settled — it can report a transient/wrong leader (winner is null
  # and the penalties field lags). Once we mark the match finished we stop polling it
  # (DueMatchSyncQuery excludes finished), so that transient value freezes and mis-scores
  # every advance pick. SyncMatch enqueues this at staggered offsets after the match
  # finishes level, so we re-read once the feed has settled and converge on the real
  # winner.
  #
  # Idempotent: resolves the advancing team from the settled fullTime aggregate and only
  # writes (and re-scores) when it differs from what's stored. A run that still cannot
  # resolve a winner (feed not settled) leaves the match untouched for a later run.
  class ReconcileShootoutAdvance < Service
    def initialize(match:, client: Client.new)
      @match = match
      @client = client
    end

    def call
      return success(changed: false) unless reconcilable?

      resolved = resolved_advancing_id
      return success(changed: false) if resolved.nil? || resolved == @match.advancing_team_id

      @match.update!(advancing_team_id: resolved)
      invoke { Scoring::ComputeMatchScores.call(match: @match) }
      log_info("ReconcileShootoutAdvance: match ##{@match.id} advancing -> #{resolved}, re-scored")
      success(changed: true, advancing_team_id: resolved)
    end

    private

    # Only a finished knockout that ended level on 90' (decided in ET or penalties)
    # needs reconciling; everything else already carries a clear result.
    def reconcilable?
      @match.status_finished? && !@match.phase_group_stage? && @match.home_score == @match.away_score
    end

    # The settled advancing team from a fresh feed read: winner when the feed has
    # populated it, otherwise the fullTime aggregate (which carries the penalty-inclusive
    # total). nil when the feed has not settled into a decisive result yet.
    def resolved_advancing_id
      score = @client.match(@match.external_id, cache_ttl: 0)["score"] || {}

      case score["winner"]
      when "HOME_TEAM" then @match.home_team_id
      when "AWAY_TEAM" then @match.away_team_id
      else
        ft = score["fullTime"] || {}
        home, away = ft["home"], ft["away"]
        return nil unless home && away && home != away

        home > away ? @match.home_team_id : @match.away_team_id
      end
    end
  end
end
