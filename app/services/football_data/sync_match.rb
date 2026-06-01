# frozen_string_literal: true

module FootballData
  # Targeted refresh of a single match from football-data.org, used by the live
  # polling job. Pulls the match detail, applies status/score/kickoff/events,
  # and reacts to the resulting transition:
  #
  #   * scheduled -> live: nothing extra (the lock job was scheduled at create).
  #   * -> finished:       enqueue MatchScoringJob (once; idempotent).
  #   * kickoff moved while still scheduled: the Match after_commit callback
  #     cancels and reschedules MatchLockJob, so nothing is done here.
  #
  # The update runs inside with_lock so concurrent polls can't interleave.
  class SyncMatch < Service
    # Live scores change constantly, so we bypass the client's 5-minute default
    # cache. A tiny non-zero TTL (rather than 0) still serves the SAME match
    # from cache if two polls overlap within the window — a cheap guard against
    # bursting the 10 req/min limit — while staying effectively fresh for the
    # 60s polling cadence.
    LIVE_CACHE_TTL = 10.seconds

    def initialize(match:, client: Client.new)
      @match = match
      @client = client
    end

    def call
      newly_finished = false

      @match.with_lock do
        was_finished = @match.status_finished?
        apply(@client.match(@match.external_id, cache_ttl: LIVE_CACHE_TTL))
        @match.save!
        newly_finished = @match.status_finished? && !was_finished
      end

      MatchScoringJob.perform_later(@match.id) if newly_finished
      success(@match)
    end

    private

    def apply(data)
      @match.status = SyncFixtures::STATUS_MAP.fetch(data["status"], @match.status)

      # Users predict the 90-minute result; ET/penalties only decide who
      # advances. regularTime carries the post-90' score for ET/penalty matches;
      # matches settled in 90' (all of the group stage) have no regularTime and
      # fall back to fullTime — unchanged behavior there.
      score = data["score"] || {}
      result = score["regularTime"] || score["fullTime"] || {}
      @match.home_score = result["home"] unless result["home"].nil?
      @match.away_score = result["away"] unless result["away"].nil?

      # winner already reflects ET/penalties, so we never derive it from goals.
      @match.advancing_team_id = advancing_team_id_from(score["winner"])

      @match.minute = live_minute(data)
      @match.kickoff_at = Time.zone.parse(data["utcDate"]) if data["utcDate"].present?
      @match.events_log = Array(data["goals"]) if data.key?("goals")
      @match.last_synced_at = Time.current
    end

    # Knockout advancing team from score.winner. nil for the group stage (which
    # has no advancing team) and for DRAW / missing / unknown winner — anomalous
    # for a finished KO, so it's logged.
    def advancing_team_id_from(winner)
      return nil if @match.phase_group_stage?

      case winner
      when "HOME_TEAM" then @match.home_team_id
      when "AWAY_TEAM" then @match.away_team_id
      else
        if @match.status_finished?
          log_info("KO match #{@match.external_id} finished without a resolvable winner: #{winner.inspect}")
        end
        nil
      end
    end

    # Resolve the match minute from the live payload:
    #   * scheduled       -> nil (a match that hasn't kicked off has no minute).
    #   * minute present  -> mirror it (covers live, and a final minute such as
    #                        90 / 90+ stamped on the finished payload).
    #   * minute absent   -> keep the last synced value rather than clobbering a
    #                        known final minute (some finished payloads drop it).
    def live_minute(data)
      return nil if @match.status_scheduled?
      return data["minute"] if data.key?("minute")

      @match.minute
    end
  end
end
