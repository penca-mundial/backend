# frozen_string_literal: true

require "rails_helper"

RSpec.describe DueMatchSyncQuery do
  include ActiveSupport::Testing::TimeHelpers

  subject(:due) { described_class.call }

  around { |example| freeze_time { example.run } }

  it "includes live matches" do
    live = create(:match, :live, kickoff_at: 1.hour.ago)
    expect(due).to include(live)
  end

  it "includes soon-to-start scheduled matches never synced" do
    match = create(:match, kickoff_at: 3.hours.from_now, last_synced_at: nil)
    expect(due).to include(match)
  end

  it "includes soon-to-start scheduled matches last synced over 6h ago" do
    match = create(:match, kickoff_at: 3.hours.from_now, last_synced_at: 7.hours.ago)
    expect(due).to include(match)
  end

  it "excludes soon-to-start scheduled matches synced within the last 6h" do
    match = create(:match, kickoff_at: 3.hours.from_now, last_synced_at: 1.hour.ago)
    expect(due).not_to include(match)
  end

  it "excludes scheduled matches starting beyond 24h" do
    match = create(:match, kickoff_at: 2.days.from_now, last_synced_at: nil)
    expect(due).not_to include(match)
  end

  it "excludes finished matches" do
    match = create(:match, :finished, kickoff_at: 2.hours.ago)
    expect(due).not_to include(match)
  end
end
