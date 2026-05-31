# frozen_string_literal: true

module FootballData
  # Orchestrates a polling tick: refreshes every match DueMatchSyncQuery selects
  # (live matches, plus soon-to-start scheduled matches that are due) by running
  # SyncMatch on each. Returns the number of matches synced. A failing single
  # match does not abort the batch — SyncMatch swallows its own errors into a
  # ServiceResult.
  class SyncDueMatches < Service
    def initialize(client: Client.new)
      @client = client
    end

    def call
      matches = DueMatchSyncQuery.call.to_a
      matches.each { |match| SyncMatch.call(match: match, client: @client) }
      success(synced: matches.size)
    end
  end
end
