# frozen_string_literal: true

# Scores every tournament-wide prediction via Scoring::ComputeTournamentScores.
# Enqueued by FootballData::SyncMatch when the FINAL transitions to 'finished'
# (with a delay, so the scorers feed settles). Thin: it invokes the service and,
# because this is the tournament's one-shot terminal scoring, re-raises on
# failure so the result is retried rather than silently lost.
class TournamentScoringJob < ApplicationJob
  queue_as :scoring

  # Retries both infra errors that escape the service AND service-level failures
  # (which #perform re-raises) — see the rationale there. ComputeTournamentScores
  # is idempotent, so retrying is safe.
  retry_on StandardError, attempts: 3

  # Declared after retry_on so it takes precedence for RecordNotFound: a deleted
  # tournament won't come back, so there's nothing to retry.
  discard_on ActiveRecord::RecordNotFound

  def perform(tournament_id)
    result = Scoring::ComputeTournamentScores.call(tournament: Tournament.find(tournament_id))

    if result.success?
      Rails.logger.info(
        "TournamentScoringJob: scored #{result.data[:count]} prediction(s) for tournament #{tournament_id}"
      )
    else
      message = "TournamentScoringJob: scoring failed for tournament #{tournament_id}: #{result.errors.to_sentence}"
      Rails.logger.error(message)
      # This is the tournament's terminal scoring: it runs once (final + 30 min)
      # with no re-trigger, so a failure must NOT complete silently. Re-raise so
      # retry_on retries (ComputeTournamentScores is idempotent); once the 3
      # attempts are exhausted, ActiveJob routes it to failed jobs — visible,
      # not a lost log line.
      raise message
    end
  end
end
