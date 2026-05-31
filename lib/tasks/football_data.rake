# frozen_string_literal: true

# One-time fixture loader for a fresh deploy. Thin wrapper around
# FootballData::SyncFixtures; output is for the human running the task.
namespace :football_data do
  desc "Populate teams, players and matches for the World Cup from football-data.org"
  task bootstrap: :environment do
    result = FootballData::SyncFixtures.call
    abort("football-data bootstrap failed: #{result.errors.join('; ')}") if result.failure?

    counts = result.data
    puts "football-data bootstrap complete:"
    puts "  teams synced:   #{counts[:teams_synced]}"
    puts "  players synced: #{counts[:players_synced]}"
    puts "  matches synced: #{counts[:matches_synced]}"
  end
end
