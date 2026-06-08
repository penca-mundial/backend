# frozen_string_literal: true

require "rails_helper"

RSpec.describe GroupEvolutionQuery do
  let(:tournament) { create(:tournament) }
  let(:owner) { create(:user) }
  let(:group) { create(:group, owner: owner) }

  # Enough finished matches to open the gate (AC3 threshold is 5).
  def open_the_gate!
    create_list(:match, GroupEvolutionQuery::MIN_FINISHED_MATCHES, :finished, tournament: tournament)
  end

  def member(username)
    create(:user, username: username).tap { |u| create(:group_membership, group: group, user: u) }
  end

  # A global snapshot row for a user on a given UTC day.
  def snapshot(user, day:, points:, exact: 0, rank: 1)
    create(:ranking_snapshot, user: user, tournament: tournament, group: nil,
                              snapshot_at: day.to_time(:utc), points: points, exact_count: exact, rank_position: rank)
  end

  describe "the gate (AC3)" do
    it "is unavailable with fewer than 5 finished matches" do
      create_list(:match, 4, :finished, tournament: tournament)
      user = member("alice")

      result = described_class.call(group: group, tournament: tournament, user: user)

      expect(result.available).to be(false)
      expect(result.lines).to eq([])
    end

    it "becomes available at exactly 5 finished matches" do
      open_the_gate!
      user = member("alice")
      snapshot(user, day: Date.new(2026, 6, 1), points: 10)

      result = described_class.call(group: group, tournament: tournament, user: user)

      expect(result.available).to be(true)
    end
  end

  describe "the series (AC2)" do
    before { open_the_gate! }

    it "builds points from the snapshot and rank among members with leaderboard tiebreaks" do
      alice = member("alice")
      bob   = member("bob")
      d1 = Date.new(2026, 6, 1)
      d2 = Date.new(2026, 6, 2)
      # Day 1: alice 10 (rank 1), bob 5 (rank 2).
      snapshot(alice, day: d1, points: 10)
      snapshot(bob,   day: d1, points: 5)
      # Day 2: tie on points (8/8) broken by exact_count -> bob ahead.
      snapshot(alice, day: d2, points: 8, exact: 1)
      snapshot(bob,   day: d2, points: 8, exact: 3)

      lines = described_class.call(group: group, tournament: tournament, user: alice).lines
      alice_series = lines.find { |l| l.user_id == alice.id }.series

      expect(alice_series).to eq([
        { date: "2026-06-01", points: 10, rank: 1 },
        { date: "2026-06-02", points: 8, rank: 2 }
      ])
    end

    it "shares a rank on a full tie (points and exact_count equal)" do
      alice = member("alice")
      bob   = member("bob")
      d = Date.new(2026, 6, 1)
      snapshot(alice, day: d, points: 7, exact: 2)
      snapshot(bob,   day: d, points: 7, exact: 2)

      lines = described_class.call(group: group, tournament: tournament, user: alice).lines

      expect(lines.map { |l| l.series.first[:rank] }).to all(eq(1))
    end

    it "ranks among group members only, ignoring non-members in the global snapshot" do
      alice = member("alice")
      outsider = create(:user, username: "outsider") # NOT a group member
      d = Date.new(2026, 6, 1)
      snapshot(outsider, day: d, points: 999) # would be rank 1 globally
      snapshot(alice, day: d, points: 10)

      lines = described_class.call(group: group, tournament: tournament, user: alice).lines

      expect(lines.find { |l| l.user_id == alice.id }.series.first[:rank]).to eq(1)
    end
  end

  describe "the line-set (top 4 + user)" do
    before { open_the_gate! }

    def seed_member_with_points(username, points)
      user = member(username)
      snapshot(user, day: Date.new(2026, 6, 1), points: points)
      user
    end

    it "returns the top 4 plus the user as the 5th line when the user is outside the top 4" do
      top = %w[top_a top_b top_c top_d].each_with_index.map { |name, i| seed_member_with_points(name, 100 - i) }
      me = seed_member_with_points("the_user", 1) # last place
      seed_member_with_points("other", 2)  # another low member, must be excluded

      lines = described_class.call(group: group, tournament: tournament, user: me).lines

      expect(lines.map(&:user_id)).to eq(top.map(&:id) + [ me.id ])
    end

    it "adds the 5th member when the user is already in the top 4" do
      members = %w[mem_a mem_b mem_c mem_d mem_e mem_f].each_with_index.map do |name, i|
        seed_member_with_points(name, 100 - i)
      end
      me = members.first # rank 1

      lines = described_class.call(group: group, tournament: tournament, user: me).lines

      expect(lines.size).to eq(5)
      expect(lines.map(&:user_id)).to eq(members.first(5).map(&:id))
    end

    it "returns every member when the group has fewer than 5" do
      members = %w[only_a only_b only_c].map.with_index { |name, i| seed_member_with_points(name, 30 - i) }

      lines = described_class.call(group: group, tournament: tournament, user: members.last).lines

      expect(lines.map(&:user_id)).to match_array(members.map(&:id))
    end
  end

  it "reads the snapshots in a single query (no N+1 across members)" do
    open_the_gate!
    5.times { |i| snapshot(member("mem_#{i}"), day: Date.new(2026, 6, 1), points: 10 - i) }

    snapshot_queries = 0
    counter = lambda do |_name, _start, _finish, _id, payload|
      snapshot_queries += 1 if payload[:sql].include?('FROM "ranking_snapshots"')
    end

    ActiveSupport::Notifications.subscribed(counter, "sql.active_record") do
      described_class.call(group: group, tournament: tournament, user: User.find_by(username: "mem_0"))
    end

    expect(snapshot_queries).to eq(1)
  end
end
