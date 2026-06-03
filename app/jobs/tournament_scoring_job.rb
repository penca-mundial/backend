# frozen_string_literal: true

# Scores every tournament-wide prediction via Scoring::ComputeTournamentScores.
# Enqueued by FootballData::SyncMatch when the FINAL transitions to 'finished'
# (with a delay, so the scorers feed settles). Thin: it just invokes the service
# and logs the outcome.
class TournamentScoringJob < ApplicationJob
  queue_as :scoring

  # Backstop for transient/infra errors that escape the service. Like
  # ComputeMatchScores, ComputeTournamentScores captures StandardError into
  # result.errors, so a deterministic scoring failure is logged (not retried);
  # this only catches what slips past the service.
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
      # Scoring failures are deterministic — log and stop, don't re-raise/retry.
      Rails.logger.error(
        "TournamentScoringJob: scoring failed for tournament #{tournament_id}: #{result.errors.to_sentence}"
      )
    end
  end
end
