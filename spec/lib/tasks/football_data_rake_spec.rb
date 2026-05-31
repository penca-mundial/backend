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

  before do
    Rake::Task["football_data:bootstrap"].reenable
    Rake::Task["football_data:bootstrap_standings"].reenable
  end

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

    # End-to-end (real SyncFixtures, stubbed HTTP) over the scenario that
    # motivated SCRUM-252: a seeded team already exists, and bootstrap is run
    # twice. Neither run may raise PG::UniqueViolation.
    context "when run twice against a seeded DB" do
      let(:base) { "https://api.football-data.org/v4" }
      let(:json) { { "Content-Type" => "application/json" } }
      let(:team_payload) do
        { "id" => 1, "name" => "Argentina", "tla" => "ARG", "crest" => "https://c/arg.png", "squad" => [] }
      end

      before do
        tournament = create(:tournament)
        create(:team, tournament: tournament, code3: "ARG", external_id: "wc2026-arg", name: "Argentina")

        stub_request(:get, "#{base}/competitions/WC")
          .to_return(status: 200, body: { "id" => 2000, "name" => "FIFA World Cup" }.to_json, headers: json)
        stub_request(:get, "#{base}/competitions/WC/teams")
          .to_return(status: 200, body: { "teams" => [ team_payload ] }.to_json, headers: json)
        stub_request(:get, "#{base}/competitions/WC/matches")
          .to_return(status: 200, body: { "matches" => [] }.to_json, headers: json)
      end

      it "is a no-op the second time, with no duplicate teams" do
        expect { Rake::Task["football_data:bootstrap"].invoke }.not_to raise_error
        Rake::Task["football_data:bootstrap"].reenable
        expect { Rake::Task["football_data:bootstrap"].invoke }.not_to raise_error

        expect(Team.where(code3: "ARG").count).to eq(1)
      end
    end
  end

  describe "football_data:bootstrap_standings" do
    it "syncs a single tournament when given its id" do
      tournament = create(:tournament, external_code: "WC")
      allow(FootballData::SyncStandings).to receive(:call)
        .and_return(ServiceResult.new(data: { standings_synced: 4 }))

      expect { Rake::Task["football_data:bootstrap_standings"].invoke(tournament.id.to_s) }
        .to output(/standings synced for .*: 4 rows/).to_stdout
      expect(FootballData::SyncStandings).to have_received(:call).with(tournament: tournament)
    end

    it "syncs all active tournaments when no id is given" do
      allow(FootballData::SyncActiveStandings).to receive(:call)
        .and_return(ServiceResult.new(data: { tournaments_synced: 2 }))

      expect { Rake::Task["football_data:bootstrap_standings"].invoke }
        .to output(/standings synced for 2 active tournament/).to_stdout
      expect(FootballData::SyncActiveStandings).to have_received(:call)
    end

    it "aborts when the sync fails" do
      allow(FootballData::SyncActiveStandings).to receive(:call)
        .and_return(ServiceResult.new(errors: [ "boom" ]))

      expect { Rake::Task["football_data:bootstrap_standings"].invoke }
        .to raise_error(SystemExit, /standings sync failed/)
    end
  end
end
