# frozen_string_literal: true

# Knockout bracket topology. Thin wrappers around Brackets::BuildTopology and the
# preview seed; output is for the human running the task.
namespace :bracket do
  desc "Build the knockout bracket topology (feeds_into / bracket_position) for a tournament (by id), or the current"
  task :build, [ :tournament_id ] => :environment do |_task, args|
    tournament = if args[:tournament_id].present?
                   Tournament.find(args[:tournament_id])
    else
                   CurrentTournamentQuery.call || abort("no current tournament")
    end

    result = Brackets::BuildTopology.call(tournament: tournament)
    abort("bracket build failed: #{result.errors.join('; ')}") if result.failure?

    puts "bracket built for #{tournament.name}: edges=#{result.data[:edges]} positions=#{result.data[:positions]}"
  end

  desc "Load the simulated demo bracket (seed b) for end-to-end preview"
  task demo: :environment do
    require Rails.root.join("db/seeds/brackets_demo")
    summary = Seeds::BracketsDemo.call
    puts "bracket demo seeded: tournament=#{summary[:tournament_id]} " \
         "edges=#{summary[:edges]} positions=#{summary[:positions]}"
  end
end
