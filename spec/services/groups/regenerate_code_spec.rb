# frozen_string_literal: true

require "rails_helper"

RSpec.describe Groups::RegenerateCode do
  let(:owner) { create(:user) }
  let(:group) { create(:group, owner: owner) }

  it "rotates the group's code to a new valid, persisted value" do
    old_code = group.code

    result = described_class.call(owner: owner, group: group)

    expect(result).to be_success
    new_code = group.reload.code
    expect(new_code).not_to eq(old_code)
    expect(new_code).to match(/\A[A-Z0-9]{8}\z/)
  end

  it "fails when the caller is not the owner" do
    old_code = group.code

    result = described_class.call(owner: create(:user), group: group)

    expect(result).to be_failure
    expect(result.errors).to include(I18n.t("services.groups.not_owner"))
    expect(group.reload.code).to eq(old_code)
  end
end
