# frozen_string_literal: true

require "rails_helper"

RSpec.describe Group, type: :model do
  it "has a valid factory" do
    expect(build(:group)).to be_valid
  end

  describe "associations" do
    it { is_expected.to belong_to(:owner).class_name("User") }
    it { is_expected.to have_many(:memberships).class_name("GroupMembership") }
    it { is_expected.to have_many(:users).through(:memberships) }
  end

  describe "validations" do
    it { is_expected.to validate_length_of(:name).is_at_least(3).is_at_most(50) }

    it "rejects a code that is not 8 uppercase alphanumerics" do
      group = build(:group, code: "bad")
      group.validate

      expect(group.errors[:code]).to be_present
    end
  end

  describe "code generation" do
    it "assigns an 8-character uppercase code on create" do
      expect(create(:group).code).to match(/\A[A-Z0-9]{8}\z/)
    end

    it "regenerates the code on collision" do
      existing = create(:group)
      owner = create(:user)
      allow(SecureRandom).to receive(:alphanumeric).with(8)
                                                    .and_return(existing.code, "freshcod")

      group = create(:group, owner: owner)

      expect(group.code).to eq("FRESHCOD")
    end
  end

  describe "owner group limit" do
    it "prevents owning more than 3 non-general groups" do
      owner = create(:user)
      create_list(:group, 3, owner: owner)

      fourth = build(:group, owner: owner)

      expect(fourth.save).to be(false)
      expect(fourth.errors[:base]).to be_present
    end

    it "does not count general-pool groups toward the limit" do
      owner = create(:user)
      create_list(:group, 3, owner: owner)

      general = build(:group, :general_pool, owner: owner)

      expect(general.save).to be(true)
    end
  end

  describe "general-pool uniqueness" do
    it "allows only one group flagged as the general pool" do
      create(:group, :general_pool)

      expect { create(:group, :general_pool) }.to raise_error(ActiveRecord::RecordNotUnique)
    end
  end

  describe "soft delete" do
    it "is hidden by the default scope after soft_delete!" do
      group = create(:group)
      group.soft_delete!

      expect(described_class.find_by(id: group.id)).to be_nil
      expect(described_class.unscoped.find_by(id: group.id)).to eq(group)
    end

    it "reappears after restore!" do
      group = create(:group)
      group.soft_delete!
      group.restore!

      expect(described_class.find_by(id: group.id)).to eq(group)
    end
  end
end
