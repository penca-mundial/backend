# frozen_string_literal: true

require "rails_helper"
require "fugit" # solid_queue's schedule parser; not autoloaded in the test env

RSpec.describe SnapshotCleanupJob do
  it "runs on the :default queue" do
    expect(described_class.queue_name).to eq("default")
  end

  describe "#perform" do
    it "delegates to Rankings::CleanupOldSnapshots and logs the deleted count" do
      allow(Rankings::CleanupOldSnapshots).to receive(:call).and_return(ServiceResult.new(data: { count: 5 }))
      allow(Rails.logger).to receive(:info)

      described_class.perform_now

      expect(Rankings::CleanupOldSnapshots).to have_received(:call).with(no_args)
      expect(Rails.logger).to have_received(:info).with(/deleted 5 snapshot/)
    end

    it "logs the errors and does not re-raise when the cleanup fails" do
      allow(Rankings::CleanupOldSnapshots).to receive(:call).and_return(ServiceResult.new(errors: [ "boom" ]))
      allow(Rails.logger).to receive(:error)

      expect { described_class.perform_now }.not_to raise_error
      expect(Rails.logger).to have_received(:error).with(/boom/)
    end

    it "deletes only the snapshots older than the 60-day retention window" do
      old_snapshot = create(:ranking_snapshot, snapshot_at: 61.days.ago)
      recent_snapshot = create(:ranking_snapshot, snapshot_at: 59.days.ago)

      described_class.perform_now

      expect(RankingSnapshot.exists?(old_snapshot.id)).to be(false)
      expect(RankingSnapshot.exists?(recent_snapshot.id)).to be(true)
    end
  end

  describe "recurring schedule" do
    it "is configured to run daily at 04:00 UTC on the default queue" do
      task = Rails.application.config_for(:recurring, env: "production")[:snapshot_cleanup]

      expect(task[:class]).to eq("SnapshotCleanupJob")
      expect(task[:queue]).to eq("default")
      expect(Fugit.parse(task[:schedule]).to_cron_s).to eq("0 4 * * *")
    end
  end
end
