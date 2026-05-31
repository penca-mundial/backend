# frozen_string_literal: true

module FootballData
  # Idempotent sync of one tournament's group standings from football-data.org.
  # Patterned after SyncFixtures: fetches the standings payload using the
  # tournament's own competition code, iterates over WHATEVER group sub-tables
  # the API returns (no fixed count), and upserts one Standing row per team
  # (matched by tournament + team). Re-running updates rows in place.
  #
  # We mirror the upstream `position` as-is and never compute tiebreakers.
  #
  # Returns a ServiceResult with { standings_synced: <rows upserted> }.
  class SyncStandings < Service
    # football-data.org returns TOTAL plus optional HOME/AWAY splits per group;
    # we only want the combined table.
    TOTAL_TYPE = "TOTAL"

    def initialize(tournament:, client: Client.new)
      @tournament = tournament
      @client = client
    end

    def call
      code = @tournament.external_code.presence
      raise_service_error("Tournament ##{@tournament.id} has no external_code") if code.nil?

      synced = 0
      ActiveRecord::Base.transaction do
        standings_tables(code).each do |table|
          group = GroupNormalizer.call(table["group"])
          next if group.nil? # knockout / single-table competitions have no group

          Array(table["table"]).each do |entry|
            synced += 1 if upsert_standing(group, entry)
          end
        end
      end

      success(standings_synced: synced)
    end

    private

    # Only the combined (TOTAL) group tables; ignore HOME/AWAY breakdowns.
    def standings_tables(code)
      @client.standings(code).fetch("standings", []).select { |t| t["type"] == TOTAL_TYPE }
    end

    # Skips rows whose team is not in our DB (e.g. a TBD/placeholder team).
    def upsert_standing(group, entry)
      team = team_for(entry.dig("team", "id"))
      return false if team.nil?

      standing = Standing.find_or_initialize_by(tournament: @tournament, team: team)
      standing.update!(
        group:           group,
        position:        entry["position"],
        played_games:    entry["playedGames"] || 0,
        won:             entry["won"] || 0,
        draw:            entry["draw"] || 0,
        lost:            entry["lost"] || 0,
        goals_for:       entry["goalsFor"] || 0,
        goals_against:   entry["goalsAgainst"] || 0,
        goal_difference: entry["goalDifference"] || 0,
        points:          entry["points"] || 0,
        form:            entry["form"]
      )
      true
    end

    def team_for(external_id)
      return nil if external_id.nil?

      # One indexed lookup table per run, scoped to this tournament's teams.
      @teams_by_external_id ||= @tournament.teams.index_by(&:external_id)
      @teams_by_external_id[external_id.to_s]
    end
  end
end
