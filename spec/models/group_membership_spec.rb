# frozen_string_literal: true

require "rails_helper"

RSpec.describe GroupMembership, type: :model do
  it "has a valid factory" do
    expect(build(:group_membership)).to be_valid
  end

  describe "associations" do
    it { is_expected.to belong_to(:group) }
    it { is_expected.to belong_to(:user) }
  end

  it "does not allow the same user to join a group twice" do
    membership = create(:group_membership)
    duplicate = build(:group_membership, group: membership.group, user: membership.user)

    expect(duplicate).not_to be_valid
  end

  describe "membership capacity" do
    it "rejects a member beyond the limit of a non-general group" do
      stub_const("Group::MAX_MEMBERSHIPS", 1)
      group = create(:group)
      create(:group_membership, group: group)

      extra = build(:group_membership, group: group)

      expect(extra).not_to be_valid
      expect(extra.errors[:base]).to be_present
    end

    it "ignores the limit for the general pool" do
      stub_const("Group::MAX_MEMBERSHIPS", 1)
      group = create(:group, :general_pool)
      create(:group_membership, group: group)

      extra = build(:group_membership, group: group)

      expect(extra).to be_valid
    end
  end

  describe "general-pool removal" do
    it "cannot be destroyed when the group is the general pool" do
      membership = create(:group_membership, group: create(:group, :general_pool))

      expect(membership.destroy).to be(false)
      expect(membership.reload).to be_persisted
    end

    it "can be destroyed from a regular group" do
      membership = create(:group_membership)

      expect(membership.destroy).to be_truthy
    end
  end
end
