# frozen_string_literal: true

module FootballData
  # ADR-0007 score reconciliation: re-reads one finished match from the feed and,
  # when the settled result differs from what we stored, corrects the 90' score
  # and/or the advancing team and re-scores.
  #
  # Why this exists: once a match is finished we stop polling it (DueMatchSyncQuery
  # excludes finished), so a feed correction that lands AFTER the close — a disallowed
  # goal, a VAR reversal, a late data fix — never reaches us and the wrong result
  # freezes, mis-scoring every prediction. SyncMatch enqueues MatchReconcileJob at
  # staggered offsets when a match finishes, and each run invokes this.
  #
  # Respects manual_override: a hand-verified result is never reverted to a feed value
  # (which may itself be the wrong one the human corrected). Idempotent — it writes and
  # re-scores only the fields that actually differ, so a match already in agreement with
  # the feed is a no-op.
  class ReconcileFinishedMatch < Service
    def initialize(match:, client: Client.new)
      @match = match
      @client = client
    end

    def call
      return success(changed: false) unless reconcilable?

      score = @client.match(@match.external_id, cache_ttl: 0)["score"] || {}
      changes = divergent_attributes(score)
      return success(changed: false) if changes.empty?

      @match.update!(changes)
      invoke { Scoring::ComputeMatchScores.call(match: @match) }
      log_info("ReconcileFinishedMatch: match ##{@match.id} corrected #{changes.inspect}, re-scored")
      success(changed: true, changes: changes)
    end

    private

    def reconcilable?
      @match.status_finished? && !@match.manual_override?
    end

    # The subset of { home_score, away_score, advancing_team_id } where the settled
    # feed disagrees with what we stored. The 90' result is regularTime (falling back
    # to fullTime for matches settled in 90'), mirroring SyncMatch. An advancing team
    # that can't be resolved (feed not decisive) is left untouched rather than nulled.
    def divergent_attributes(score)
      result = score["regularTime"] || score["fullTime"] || {}
      changes = {}
      changes[:home_score] = result["home"] if result["home"] && result["home"] != @match.home_score
      changes[:away_score] = result["away"] if result["away"] && result["away"] != @match.away_score

      advancing = advancing_from(score)
      changes[:advancing_team_id] = advancing if !advancing.nil? && advancing != @match.advancing_team_id

      changes
    end

    def advancing_from(score)
      return nil if @match.phase_group_stage?

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
