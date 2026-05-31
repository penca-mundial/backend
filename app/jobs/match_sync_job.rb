# frozen_string_literal: true

# Recurring poll (every 60s, see config/recurring.yml) that refreshes live and
# soon-to-start matches from football-data.org. All the selection and sync logic
# lives in FootballData::SyncDueMatches.
class MatchSyncJob < ApplicationJob
  queue_as :sync

  def perform
    FootballData::SyncDueMatches.call
  end
end
