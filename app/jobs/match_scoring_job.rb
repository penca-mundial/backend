# frozen_string_literal: true

# Scores every prediction of a finished match via Scoring::ComputeMatchScores.
# Enqueued by FootballData::SyncMatch on the transition to 'finished' (and by an
# admin recompute). Thin: it just invokes the service and logs the outcome.
class MatchScoringJob < ApplicationJob
  queue_as :scoring

  # Backstop for transient/infra errors that escape the service. Note that
  # ComputeMatchScores already captures StandardError into result.errors, so a
  # deterministic scoring failure is logged (not retried); this only catches
  # what slips past the service.
  retry_on StandardError, attempts: 3

  # Declared after retry_on so it takes precedence for RecordNotFound: a deleted
  # match won't come back, so there's nothing to retry.
  discard_on ActiveRecord::RecordNotFound

  def perform(match_id)
    match = Match.find(match_id)
    result = Scoring::ComputeMatchScores.call(match: match)

    if result.success?
      Rails.logger.info("MatchScoringJob: scored #{result.data[:count]} prediction(s) for match #{match_id}")
    else
      # Scoring failures are deterministic — log and stop, don't re-raise/retry.
      Rails.logger.error("MatchScoringJob: scoring failed for match #{match_id}: #{result.errors.to_sentence}")
    end

    # Chain a ranking-snapshot attempt for THIS match's UTC day. Passing the day
    # (not "now") keeps it correct if the job runs past midnight UTC.
    # RankingSnapshotJob no-ops until the day's last match is finished, and is
    # idempotent, so triggering once per scored match is safe.
    RankingSnapshotJob.perform_later(match.kickoff_at.utc.to_date.iso8601)
  end
end
