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

    if result.success?
      Rails.logger.info("FixtureResyncJob: created #{result.data[:matches_created]} newly-resolved match(es)")
    else
      Rails.logger.error("FixtureResyncJob: incremental fixtures re-sync failed: #{result.errors.to_sentence}")
    end
  end
end
