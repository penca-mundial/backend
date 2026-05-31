# frozen_string_literal: true

require "rails_helper"

RSpec.describe MatchSyncJob do
  include ActiveSupport::Testing::TimeHelpers

  it "uses the :sync queue" do
    expect(described_class.queue_name).to eq("sync")
  end

  describe "#perform" do
    around { |example| freeze_time { example.run } }

    before { allow(FootballData::SyncMatch).to receive(:call).and_return(ServiceResult.new) }

    it "syncs live matches and due scheduled matches, and nothing else" do
      live          = create(:match, :live, kickoff_at: 1.hour.ago)
      soon_unsynced = create(:match, kickoff_at: 2.hours.from_now, last_synced_at: nil)
      soon_stale    = create(:match, kickoff_at: 5.hours.from_now, last_synced_at: 7.hours.ago)
      soon_fresh    = create(:match, kickoff_at: 5.hours.from_now, last_synced_at: 1.hour.ago)
      far_off       = create(:match, kickoff_at: 2.days.from_now, last_synced_at: nil)
      finished      = create(:match, :finished, kickoff_at: 3.hours.ago)

      described_class.perform_now

      [ live, soon_unsynced, soon_stale ].each do |match|
        expect(FootballData::SyncMatch).to have_received(:call).with(match: match, client: anything)
      end
      [ soon_fresh, far_off, finished ].each do |match|
        expect(FootballData::SyncMatch).not_to have_received(:call).with(match: match, client: anything)
      end
      expect(FootballData::SyncMatch).to have_received(:call).exactly(3).times
    end
  end

  it "runs without error and syncs nothing when there are no due matches" do
    allow(FootballData::SyncMatch).to receive(:call)

    expect { described_class.perform_now }.not_to raise_error
    expect(FootballData::SyncMatch).not_to have_received(:call)
  end
end
