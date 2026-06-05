# frozen_string_literal: true

require "rails_helper"

RSpec.describe Groups::CreateGroup do
  let(:owner) { create(:user) }

  describe "#call" do
    it "creates the group and adds the owner as its first member" do
      result = described_class.call(owner: owner, name: "Los Cracks", description: "vamos arriba")

      expect(result).to be_success
      group = result.data[:group]
      expect(group).to be_persisted
      expect(group).to have_attributes(
        owner: owner, name: "Los Cracks", description: "vamos arriba", is_general_pool: false
      )
      expect(group.users).to contain_exactly(owner)
    end

    it "assigns an 8-character [A-Z0-9] code" do
      group = described_class.call(owner: owner, name: "Con codigo").data[:group]

      expect(group.code).to match(/\A[A-Z0-9]{8}\z/)
    end

    it "creates the owner's membership pointing at the group and user" do
      group = described_class.call(owner: owner, name: "Con membership").data[:group]

      membership = GroupMembership.find_by(group: group, user: owner)
      expect(membership).to have_attributes(group: group, user: owner)
    end

    it "fails and rolls back when the name is too short" do
      result = described_class.call(owner: owner, name: "ab")

      expect(result).to be_failure
      expect(result.errors).to be_present
      expect(Group.count).to eq(0)
      expect(GroupMembership.count).to eq(0)
    end

    it "fails when the name is too long" do
      result = described_class.call(owner: owner, name: "a" * 51)

      expect(result).to be_failure
      expect(result.errors).to be_present
    end

    context "with the owner already at the owned-group limit" do
      before { create_list(:group, Group::MAX_OWNED_GROUPS, owner: owner) }

      it "fails with a readable too_many_owned_groups message (not the raw symbol)" do
        result = described_class.call(owner: owner, name: "Cuarto grupo")

        expect(result).to be_failure
        expect(result.errors).to include("no podés tener más de 3 grupos activos")
        expect(GroupMembership.count).to eq(0) # owner membership never created
      end

      it "allows creation when one of the owner's groups is soft-deleted (it doesn't count)" do
        owner.owned_groups.first.soft_delete!

        result = described_class.call(owner: owner, name: "Reemplazo")

        expect(result).to be_success
        expect(result.data[:group].users).to contain_exactly(owner)
      end
    end
  end
end
