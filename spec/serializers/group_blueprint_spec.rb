# frozen_string_literal: true

require "rails_helper"

RSpec.describe GroupBlueprint do
  it "exposes the owner's username for user-owned groups" do
    owner = create(:user, username: "captain")
    group = create(:group, owner: owner)

    expect(described_class.render_as_hash(group)[:owner_username]).to eq("captain")
  end

  it "hides a system owner (the general pool case): owner_username is nil" do
    group = create(:group, owner: create(:user, :system))

    expect(described_class.render_as_hash(group)[:owner_username]).to be_nil
  end
end
