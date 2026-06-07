# frozen_string_literal: true

require "rails_helper"

RSpec.describe Rankings::CleanupOldSnapshots do
  include ActiveSupport::Testing::TimeHelpers

  def snapshot_at(time)
    create(:ranking_snapshot, snapshot_at: time)
  end

  describe "#call" do
    it "deletes snapshots older than the retention threshold" do
      old = snapshot_at(70.days.ago)

      result = described_class.call

      expect(RankingSnapshot.exists?(old.id)).to be(false)
      expect(result).to be_success
      expect(result.data).to eq(count: 1)
    end

    it "keeps snapshots within the retention window" do
      recent = snapshot_at(10.days.ago)

      described_class.call

      expect(RankingSnapshot.exists?(recent.id)).to be(true)
    end

    it "keeps a snapshot exactly at the cutoff (strict <, not <=)" do
      freeze_time do
        at_cutoff = snapshot_at(60.days.ago) # == retention_days.days.ago at call time
        just_older = snapshot_at(60.days.ago - 1.second)

        result = described_class.call

        expect(RankingSnapshot.exists?(at_cutoff.id)).to be(true)   # boundary kept
        expect(RankingSnapshot.exists?(just_older.id)).to be(false) # one second older swept
        expect(result.data).to eq(count: 1)
      end
    end

    it "defaults to a 60-day retention" do
      snapshot_at(61.days.ago)
      snapshot_at(59.days.ago)

      expect(described_class.call.data).to eq(count: 1)
    end

    it "respects a custom retention_days" do
      snapshot_at(40.days.ago)
      kept = snapshot_at(20.days.ago)

      result = described_class.call(retention_days: 30)

      expect(result.data).to eq(count: 1)
      expect(RankingSnapshot.exists?(kept.id)).to be(true)
    end

    it "returns count 0 and success when there is nothing to delete" do
      snapshot_at(1.day.ago)

      result = described_class.call

      expect(result).to be_success
      expect(result.data).to eq(count: 0)
    end

    it "returns the exact number of rows deleted" do
      3.times { |i| snapshot_at((70 + i).days.ago) }
      snapshot_at(5.days.ago)

      expect(described_class.call.data).to eq(count: 3)
    end
  end
end
