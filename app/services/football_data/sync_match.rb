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
    def initialize(match:, client: Client.new)
      @match = match
      @client = client
    end

    def call
      newly_finished = false

      @match.with_lock do
        was_finished = @match.status_finished?
        apply(@client.match(@match.external_id))
        @match.save!
        newly_finished = @match.status_finished? && !was_finished
      end

      MatchScoringJob.perform_later(@match.id) if newly_finished
      success(@match)
    end

    private

    def apply(data)
      @match.status = SyncFixtures::STATUS_MAP.fetch(data["status"], @match.status)

      score = data["score"]&.dig("fullTime") || {}
      @match.home_score = score["home"] unless score["home"].nil?
      @match.away_score = score["away"] unless score["away"].nil?

      @match.kickoff_at = Time.zone.parse(data["utcDate"]) if data["utcDate"].present?
      @match.events_log = Array(data["goals"]) if data.key?("goals")
      @match.last_synced_at = Time.current
    end
  end
end
