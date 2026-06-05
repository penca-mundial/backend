# frozen_string_literal: true

require "rails_helper"

RSpec.describe Groups::DeleteGroup do
  let(:owner) { create(:user) }
  let(:group) { create(:group, owner: owner) }

  it "soft-deletes the group for its owner" do
    result = described_class.call(owner: owner, group: group)

    expect(result).to be_success
    expect(group.reload.deleted_at).to be_present
    expect(Group.where(id: group.id)).to be_empty # hidden by the default scope
  end

  it "fails when the caller is not the owner" do
    result = described_class.call(owner: create(:user), group: group)

    expect(result).to be_failure
    expect(result.errors).to include(I18n.t("services.groups.not_owner"))
    expect(group.reload.deleted_at).to be_nil
  end

  it "fails for the general pool" do
    pool = create(:group, :general_pool, owner: owner)

    result = described_class.call(owner: owner, group: pool)

    expect(result).to be_failure
    expect(result.errors).to include(I18n.t("services.groups.cannot_delete_general_pool"))
    expect(pool.reload.deleted_at).to be_nil
  end
end
