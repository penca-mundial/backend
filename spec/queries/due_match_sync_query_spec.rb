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

  # SCRUM-313 root cause: the three buckets (live, started, upcoming-stale) must
  # ALL be selected on the same tick. The old chained `.or` of `where(id: ...)`
  # relations silently dropped the started branch from the generated SQL, so a
  # scheduled match past its kickoff never flipped to live on its own. Pairs of
  # buckets worked, which is why the suite stayed green — only all three together
  # exposes it. This is THE regression test.
  it "selects live, started, and upcoming-stale matches all on the same tick" do
    live     = create(:match, :live, kickoff_at: 30.minutes.ago)
    started  = create(:match, kickoff_at: 30.minutes.ago, last_synced_at: 1.minute.ago)
    upcoming = create(:match, kickoff_at: 3.hours.from_now, last_synced_at: nil)

    expect(due).to include(live, started, upcoming)
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

  # SCRUM-313: a scheduled match whose kickoff has already passed but the feed
  # hasn't flipped to live yet. The old `now..(now + horizon)` lower bound
  # excluded these, so once a match became stale AFTER its kickoff it dropped out
  # of the window forever and was never polled again — the dead-window deadlock.
  context "with overdue scheduled matches (kickoff already passed, still scheduled)" do
    it "includes one that is also stale" do
      match = create(:match, kickoff_at: 5.minutes.ago, last_synced_at: 7.hours.ago)
      expect(due).to include(match)
    end

    it "includes one even when recently synced — poll every tick until it flips live" do
      match = create(:match, kickoff_at: 5.minutes.ago, last_synced_at: 1.minute.ago)
      expect(due).to include(match)
    end

    it "includes the exact deadlock case: staleness boundary fell just after kickoff" do
      # Synced 6h+ ago, kicked off 4 min ago. Before kickoff it wasn't yet stale;
      # by the time it went stale its kickoff had passed and the window dropped it.
      match = create(:match, kickoff_at: 4.minutes.ago, last_synced_at: 6.hours.ago - 4.minutes)
      expect(due).to include(match)
    end

    it "excludes one whose kickoff is older than the horizon (a stuck zombie, not a live-imminent match)" do
      match = create(:match, kickoff_at: (DueMatchSyncQuery::SCHEDULED_HORIZON + 1.hour).ago)
      expect(due).not_to include(match)
    end
  end

  context "with burst protection" do
    it "caps how many upcoming-stale matches are returned per tick" do
      cap = DueMatchSyncQuery::MAX_UPCOMING_PER_TICK
      (cap + 3).times { |i| create(:match, kickoff_at: (i + 1).hours.from_now, last_synced_at: nil) }
      expect(due.to_a.size).to eq(cap)
    end

    it "never caps live or overdue (started) matches" do
      live = Array.new(DueMatchSyncQuery::MAX_UPCOMING_PER_TICK + 3) do |i|
        create(:match, :live, kickoff_at: (i + 1).minutes.ago)
      end
      expect(due).to include(*live)
    end

    it "orders live and overdue matches before upcoming ones" do
      upcoming = create(:match, kickoff_at: 3.hours.from_now, last_synced_at: nil)
      started  = create(:match, kickoff_at: 5.minutes.ago, last_synced_at: nil)
      live     = create(:match, :live, kickoff_at: 30.minutes.ago)

      ids = due.to_a.map(&:id)
      expect(ids.index(live.id)).to be < ids.index(upcoming.id)
      expect(ids.index(started.id)).to be < ids.index(upcoming.id)
    end
  end
end
