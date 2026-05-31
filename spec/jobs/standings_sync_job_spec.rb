# frozen_string_literal: true

require "rails_helper"

RSpec.describe StandingsSyncJob do
  it "uses the :sync queue" do
    expect(described_class.queue_name).to eq("sync")
  end

  describe "#perform" do
    it "delegates to FootballData::SyncActiveStandings" do
      allow(FootballData::SyncActiveStandings).to receive(:call).and_return(ServiceResult.new)

      described_class.perform_now

      expect(FootballData::SyncActiveStandings).to have_received(:call)
    end
  end
end
