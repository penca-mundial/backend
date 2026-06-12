# frozen_string_literal: true

module FootballData
  # Orchestrates a polling tick: refreshes every match DueMatchSyncQuery selects
  # (live matches, started matches awaiting their live transition, plus a capped
  # batch of soon-to-start scheduled matches that are due) by running SyncMatch
  # on each.
  #
  # Observability (SCRUM-313): every tick logs how many matches the query
  # selected — including zero, so a dead window where nothing is being polled is
  # visible in the logs instead of looking identical to a healthy idle tick. A
  # failing single match does not abort the batch (SyncMatch converts its own
  # errors into a ServiceResult), but each failure is now logged with the match
  # id and the error rather than swallowed silently.
  class SyncDueMatches < Service
    def initialize(client: Client.new)
      @client = client
    end

    def call
      matches = DueMatchSyncQuery.call.to_a
      log_info("Selected #{matches.size} match(es) to sync this tick")

      failed = 0
      matches.each do |match|
        result = SyncMatch.call(match: match, client: @client)
        next if result.success?

        failed += 1
        log_warn("SyncMatch failed for match #{match.id} (external_id=#{match.external_id}): " \
                 "#{result.errors.to_sentence}")
      end

      success(synced: matches.size - failed, failed: failed)
    end
  end
end
