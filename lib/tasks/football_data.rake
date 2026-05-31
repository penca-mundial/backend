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

  desc "Sync group standings for a tournament (by id), or all active tournaments if no id is given"
  task :bootstrap_standings, [ :tournament_id ] => :environment do |_task, args|
    if args[:tournament_id].present?
      tournament = Tournament.find(args[:tournament_id])
      result = FootballData::SyncStandings.call(tournament: tournament)
      abort("standings sync failed: #{result.errors.join('; ')}") if result.failure?
      puts "standings synced for #{tournament.name}: #{result.data[:standings_synced]} rows"
    else
      result = FootballData::SyncActiveStandings.call
      abort("standings sync failed: #{result.errors.join('; ')}") if result.failure?
      puts "standings synced for #{result.data[:tournaments_synced]} active tournament(s)"
    end
  end
end
