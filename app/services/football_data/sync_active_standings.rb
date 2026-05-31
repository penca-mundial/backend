# frozen_string_literal: true

module FootballData
  # Orchestrates a standings-refresh tick: runs SyncStandings for every active
  # tournament that has a competition code. Patterned after SyncDueMatches — a
  # single tournament failing does not abort the batch (SyncStandings swallows
  # its own errors into a ServiceResult). Returns the count of tournaments synced.
  class SyncActiveStandings < Service
    def initialize(client: Client.new)
      @client = client
    end

    def call
      tournaments = Tournament.active.where.not(external_code: [ nil, "" ]).to_a
      tournaments.each { |tournament| SyncStandings.call(tournament: tournament, client: @client) }
      success(tournaments_synced: tournaments.size)
    end
  end
end
