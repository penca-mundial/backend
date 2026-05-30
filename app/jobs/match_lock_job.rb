# frozen_string_literal: true

# Scheduled to run a minute before kickoff, this job locks every prediction for
# the match as a backstop to the real-time, service-level lock checks. Idempotent
# (see Matches::LockPredictions): a second run does not move existing locks.
class MatchLockJob < ApplicationJob
  queue_as :default

  # If the match was deleted before the job ran, there is nothing to lock.
  discard_on ActiveJob::DeserializationError

  def perform(match_id)
    match = Match.find(match_id)
    Matches::LockPredictions.call(match: match)
  end
end
