# frozen_string_literal: true

# Recurring "create-on-resolve" fixtures re-sync (every 3h, see
# config/recurring.yml). Runs FootballData::SyncFixtures in incremental mode so
# knockout matches enter the DB once the feed names both teams (ADR-0001),
# without touching the live state of existing matches. Thin: invoke + log.
class FixtureResyncJob < ApplicationJob
  queue_as :sync

  # Backstop for transient/infra errors that escape the service (which already
  # captures StandardError into result.errors). No indefinite retries.
  retry_on StandardError, attempts: 3

  def perform
    result = FootballData::SyncFixtures.call(incremental: true)

    unless result.success?
      Rails.logger.error("FixtureResyncJob: incremental fixtures re-sync failed: #{result.errors.to_sentence}")
      return
    end

    created = result.data[:matches_created]
    Rails.logger.info("FixtureResyncJob: created #{created} newly-resolved match(es)")

    # Newly-resolved knockout matches changed the bracket: rebuild its topology
    # AFTER the sync, in a separate isolated job (a build failure can't touch the
    # sync). Gated on a real change so idle resyncs don't trigger a rebuild.
    BracketBuildJob.perform_later if created.positive?
  end
end
