# frozen_string_literal: true

require "rails_helper"
require "yaml"

RSpec.describe FixtureResyncJob do
  it "runs on the :sync queue" do
    expect(described_class.queue_name).to eq("sync")
  end

  it "is registered as a recurring task on the sync queue (config/recurring.yml)" do
    config = YAML.load_file(Rails.root.join("config/recurring.yml"))
    entry = config.dig("production", "fixture_resync")

    expect(entry).to include("class" => "FixtureResyncJob", "queue" => "sync")
    expect(entry["schedule"]).to be_present
  end

  describe "#perform" do
    before { allow(BracketBuildJob).to receive(:perform_later) }

    it "runs an incremental fixtures re-sync and logs the created count on success" do
      allow(FootballData::SyncFixtures).to receive(:call).and_return(ServiceResult.new(data: { matches_created: 2 }))
      allow(Rails.logger).to receive(:info)

      described_class.perform_now

      expect(FootballData::SyncFixtures).to have_received(:call).with(incremental: true)
      expect(Rails.logger).to have_received(:info).with(/created 2/)
    end

    it "enqueues a bracket rebuild when new knockout matches were created" do
      allow(FootballData::SyncFixtures).to receive(:call).and_return(ServiceResult.new(data: { matches_created: 2 }))

      described_class.perform_now

      expect(BracketBuildJob).to have_received(:perform_later)
    end

    it "does not enqueue a bracket rebuild when nothing new was created" do
      allow(FootballData::SyncFixtures).to receive(:call).and_return(ServiceResult.new(data: { matches_created: 0 }))

      described_class.perform_now

      expect(BracketBuildJob).not_to have_received(:perform_later)
    end

    it "logs the errors and does not re-raise (nor rebuild) when the re-sync fails" do
      allow(FootballData::SyncFixtures).to receive(:call).and_return(ServiceResult.new(errors: [ "boom" ]))
      allow(Rails.logger).to receive(:error)

      expect { described_class.perform_now }.not_to raise_error
      expect(Rails.logger).to have_received(:error).with(/boom/)
      expect(BracketBuildJob).not_to have_received(:perform_later)
    end
  end
end
