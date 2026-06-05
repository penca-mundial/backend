# frozen_string_literal: true

require "rails_helper"

RSpec.describe Groups::JoinGroup do
  let(:group) { create(:group) }
  let(:user) { create(:user) }

  it "joins the user via the invite code" do
    result = described_class.call(user: user, code: group.code)

    expect(result).to be_success
    expect(result.data[:joined]).to be(true)
    expect(group.users).to include(user)
  end

  it "normalizes the code (case and surrounding whitespace)" do
    result = described_class.call(user: user, code: "  #{group.code.downcase}  ")

    expect(result).to be_success
    expect(group.reload.users).to include(user)
  end

  it "is idempotent: an existing member is returned without a new membership" do
    create(:group_membership, group: group, user: user)

    result = nil
    expect { result = described_class.call(user: user, code: group.code) }
      .not_to change(GroupMembership, :count)

    expect(result).to be_success
    expect(result.data[:joined]).to be(false)
  end

  it "fails when no group matches the code" do
    result = described_class.call(user: user, code: "NOPE0000")

    expect(result).to be_failure
    expect(result.errors).to include(I18n.t("services.groups.not_found"))
  end

  it "fails with the group_full message at capacity" do
    stub_const("Group::MAX_MEMBERSHIPS", 1)
    create(:group_membership, group: group, user: create(:user))

    result = described_class.call(user: user, code: group.code)

    expect(result).to be_failure
    expect(result.errors)
      .to include(a_string_matching(/máximo de integrantes/))
  end
end
