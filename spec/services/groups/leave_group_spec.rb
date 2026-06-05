# frozen_string_literal: true

require "rails_helper"

RSpec.describe Groups::LeaveGroup do
  let(:owner) { create(:user) }
  let(:group) { create(:group, owner: owner) }
  let(:member) { create(:user) }

  it "removes a non-owner member's membership" do
    create(:group_membership, group: group, user: member)

    result = described_class.call(user: member, group: group)

    expect(result).to be_success
    expect(group.reload.users).not_to include(member)
  end

  it "is idempotent when the user is not a member" do
    result = nil
    expect { result = described_class.call(user: member, group: group) }
      .not_to change(GroupMembership, :count)

    expect(result).to be_success
  end

  it "fails for the general pool" do
    pool = create(:group, :general_pool, owner: owner)
    create(:group_membership, group: pool, user: member)

    result = described_class.call(user: member, group: pool)

    expect(result).to be_failure
    expect(result.errors)
      .to include(I18n.t("activerecord.errors.models.group_membership.attributes.base.cannot_leave_general_pool"))
  end

  it "fails when the owner tries to leave their own group" do
    create(:group_membership, group: group, user: owner)

    result = described_class.call(user: owner, group: group)

    expect(result).to be_failure
    expect(result.errors).to include(I18n.t("services.groups.owner_cannot_leave"))
  end
end
