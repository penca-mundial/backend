# frozen_string_literal: true

require "rails_helper"

RSpec.describe Groups::KickMember do
  let(:owner) { create(:user) }
  let(:group) { create(:group, owner: owner) }
  let(:member) { create(:user) }

  it "removes the target member for the owner" do
    create(:group_membership, group: group, user: member)

    result = described_class.call(owner: owner, group: group, target_user: member)

    expect(result).to be_success
    expect(group.reload.users).not_to include(member)
  end

  it "fails when the caller is not the owner" do
    create(:group_membership, group: group, user: member)

    result = described_class.call(owner: create(:user), group: group, target_user: member)

    expect(result).to be_failure
    expect(result.errors).to include(I18n.t("services.groups.not_owner"))
  end

  it "fails when the owner targets themselves" do
    result = described_class.call(owner: owner, group: group, target_user: owner)

    expect(result).to be_failure
    expect(result.errors).to include(I18n.t("services.groups.cannot_kick_owner"))
  end

  it "fails when the target is not a member" do
    result = described_class.call(owner: owner, group: group, target_user: member)

    expect(result).to be_failure
    expect(result.errors).to include(I18n.t("services.groups.not_a_member"))
  end
end
