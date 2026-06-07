# frozen_string_literal: true

# Daily retention sweep (scheduled in config/recurring.yml): prunes
# RankingSnapshot rows older than the default 60-day window via
# Rankings::CleanupOldSnapshots. Thin: it just invokes the service and logs
# the outcome.
class SnapshotCleanupJob < ApplicationJob
  queue_as :default

  def perform
    result = Rankings::CleanupOldSnapshots.call

    if result.success?
      Rails.logger.info("SnapshotCleanupJob: deleted #{result.data[:count]} snapshot(s) past the retention window")
    else
      Rails.logger.error("SnapshotCleanupJob: cleanup failed: #{result.errors.to_sentence}")
    end
  end
end
