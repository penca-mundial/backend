# frozen_string_literal: true

# Builds the knockout bracket topology (feeds_into / bracket_position) for the
# current tournament via Brackets::BuildTopology.
#
# Enqueued by FixtureResyncJob AFTER an incremental fixtures re-sync that created
# newly-resolved knockout matches — never inside the live sync loop, and in its
# own job, so a build failure is fully isolated from the sync (the sync has
# already finished and logged). The builder is idempotent, so a duplicate run is
# a cheap no-op. Thin: resolve the tournament, invoke the service, log.
class BracketBuildJob < ApplicationJob
  queue_as :sync

  # Backstop for transient/infra errors; BuildTopology already captures
  # StandardError into result.errors, so a deterministic failure is logged, not
  # retried. The next resync rebuilds anyway (idempotent).
  retry_on StandardError, attempts: 3

  def perform
    tournament = CurrentTournamentQuery.call
    unless tournament
      Rails.logger.info("BracketBuildJob: no current tournament; skipping")
      return
    end

    result = Brackets::BuildTopology.call(tournament: tournament)

    if result.success?
      Rails.logger.info("BracketBuildJob: tournament #{tournament.id} — " \
                        "edges=#{result.data[:edges]} positions=#{result.data[:positions]}")
    else
      Rails.logger.error("BracketBuildJob: build failed for tournament #{tournament.id}: " \
                         "#{result.errors.to_sentence}")
    end
  end
end
