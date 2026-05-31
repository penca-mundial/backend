# frozen_string_literal: true

require "rails_helper"
require "rake"

# Integration test for the football_data:* rake tasks. Verifies the CLI wiring
# (task discovery, output, exit semantics); the sync logic lives in
# FootballData::SyncFixtures and is covered by its own spec.
RSpec.describe "football_data rake tasks" do # rubocop:disable RSpec/DescribeClass
  before(:all) do # rubocop:disable RSpec/BeforeAfterAll
    Rails.application.load_tasks if Rake::Task.tasks.none? { |t| t.name.start_with?("football_data:") }
  end

  before { Rake::Task["football_data:bootstrap"].reenable }

  describe "football_data:bootstrap" do
    it "runs SyncFixtures and prints the synced counts" do
      allow(FootballData::SyncFixtures).to receive(:call)
        .and_return(ServiceResult.new(data: { teams_synced: 48, players_synced: 600, matches_synced: 104 }))

      expect { Rake::Task["football_data:bootstrap"].invoke }
        .to output(/teams synced:\s+48.*players synced:\s+600.*matches synced:\s+104/m).to_stdout
      expect(FootballData::SyncFixtures).to have_received(:call)
    end

    it "aborts when the sync fails" do
      allow(FootballData::SyncFixtures).to receive(:call)
        .and_return(ServiceResult.new(errors: [ "General pool no inicializado." ]))

      expect { Rake::Task["football_data:bootstrap"].invoke }
        .to raise_error(SystemExit, /football-data bootstrap failed/)
    end
  end
end
