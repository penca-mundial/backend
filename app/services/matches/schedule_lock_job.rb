# frozen_string_literal: true

module Matches
  # Schedules MatchLockJob to fire LOCK_LEAD before kickoff. Any lock job
  # already pending for the match is cancelled first, so a rescheduled kickoff
  # never leaves a stale timer behind.
  class ScheduleLockJob < Service
    LOCK_LEAD = 1.minute

    def initialize(match:)
      @match = match
    end

    def call
      cancel_pending_lock_jobs
      MatchLockJob.set(wait_until: @match.kickoff_at - LOCK_LEAD).perform_later(@match.id)
      success
    end

    private

    # Cancellation = delete the pending SolidQueue::Job; its scheduled execution
    # row is removed by the ON DELETE cascade. Under the test/async adapters no
    # rows exist, so this is a harmless no-op.
    def cancel_pending_lock_jobs
      SolidQueue::Job
        .where(class_name: MatchLockJob.name, finished_at: nil)
        .each { |job| job.destroy if lock_job_for_match?(job) }
    end

    def lock_job_for_match?(job)
      payload = job.arguments
      payload = JSON.parse(payload) if payload.is_a?(String)
      Array(payload&.dig("arguments")).first == @match.id
    rescue JSON::ParserError
      false
    end
  end
end
