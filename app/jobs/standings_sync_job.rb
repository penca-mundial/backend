# frozen_string_literal: true

# Recurring poll (see config/recurring.yml) that refreshes group standings for
# all active tournaments from football-data.org. Selection and sync logic lives
# in FootballData::SyncActiveStandings.
class StandingsSyncJob < ApplicationJob
  queue_as :sync

  def perform
    FootballData::SyncActiveStandings.call
  end
end
