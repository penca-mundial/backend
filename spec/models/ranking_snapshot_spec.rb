# frozen_string_literal: true

require "rails_helper"

RSpec.describe RankingSnapshot, type: :model do
  it "has a valid global factory" do
    expect(build(:ranking_snapshot)).to be_valid
  end

  it "has a valid group-scoped factory" do
    expect(build(:ranking_snapshot, :for_group)).to be_valid
  end

  describe ".global" do
    it "returns only rows with a nil group_id" do
      global = create(:ranking_snapshot, group: nil)
      create(:ranking_snapshot, :for_group)

      expect(described_class.global).to contain_exactly(global)
    end
  end

  describe ".for_group" do
    it "returns only rows for the given group" do
      group = create(:group)
      scoped = create(:ranking_snapshot, group: group)
      create(:ranking_snapshot, group: nil)

      expect(described_class.for_group(group)).to contain_exactly(scoped)
    end
  end

  describe "validations" do
    it "requires snapshot_at" do
      expect(build(:ranking_snapshot, snapshot_at: nil)).not_to be_valid
    end

    it "rejects negative points" do
      expect(build(:ranking_snapshot, points: -1)).not_to be_valid
    end

    it "rejects a non-positive rank_position" do
      expect(build(:ranking_snapshot, rank_position: 0)).not_to be_valid
    end
  end
end
