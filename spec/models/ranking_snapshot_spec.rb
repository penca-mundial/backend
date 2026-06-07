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

    it "requires a tournament (even for a global snapshot)" do
      expect(build(:ranking_snapshot, tournament: nil)).not_to be_valid
    end

    it "rejects a negative exact_count" do
      expect(build(:ranking_snapshot, exact_count: -1)).not_to be_valid
    end
  end

  describe ".for_tournament" do
    it "returns only rows for the given tournament" do
      tournament = create(:tournament)
      scoped = create(:ranking_snapshot, tournament: tournament)
      create(:ranking_snapshot, tournament: create(:tournament))

      expect(described_class.for_tournament(tournament)).to contain_exactly(scoped)
    end
  end

  # The unique index uses NULLS NOT DISTINCT so the global case (group_id NULL)
  # is deduplicated by the DB — without it CaptureSnapshot would duplicate global
  # rows. There is no model-level uniqueness validation, so this is enforced at
  # the database layer (RecordNotUnique).
  describe "global-snapshot idempotency" do
    it "rejects a duplicate global row for the same (user, tournament, snapshot_at) with group_id NULL" do
      attrs = { user: create(:user), tournament: create(:tournament), group: nil, snapshot_at: Time.current }
      create(:ranking_snapshot, **attrs)

      expect { create(:ranking_snapshot, **attrs) }.to raise_error(ActiveRecord::RecordNotUnique)
    end

    it "allows the same (user, tournament, snapshot_at) across different groups" do
      user = create(:user)
      tournament = create(:tournament)
      at = Time.current
      create(:ranking_snapshot, user: user, tournament: tournament, group: create(:group), snapshot_at: at)

      expect do
        create(:ranking_snapshot, user: user, tournament: tournament, group: create(:group), snapshot_at: at)
      end.not_to raise_error
    end
  end
end
