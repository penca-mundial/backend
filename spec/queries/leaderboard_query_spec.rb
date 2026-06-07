# frozen_string_literal: true

require "rails_helper"

RSpec.describe LeaderboardQuery do
  let(:tournament) { create(:tournament) }
  # One capture = one shared snapshot_at (RankingSnapshotJob normalizes the whole
  # set to the day start); the anchor lookup matches the SET's timestamp, so rows
  # meant to be part of the same anchor MUST share `at`.
  let(:anchor_time) { 1.day.ago }
  let(:group) { create(:group, owner: create(:user)) }

  # A user with the given match points and exact-score count IN the given
  # tournament (defaults to the shared one): one 1-point exact_score per exact hit
  # plus a single non-exact score for the remainder. No group membership — the
  # global universe.
  def user_with_scores(points:, exact: 0, in_tournament: nil)
    t = in_tournament || tournament
    user = create(:user)

    exact.times do
      prediction = create(:prediction, user: user, match: create(:match, tournament: t))
      create(:prediction_score, prediction: prediction, points_result: 1, multiplier: 1.0,
                                breakdown: { "result_rule" => "exact_score" })
    end

    remaining = points - exact
    if remaining.positive?
      prediction = create(:prediction, user: user, match: create(:match, tournament: t))
      create(:prediction_score, prediction: prediction, points_result: remaining, multiplier: 1.0,
                                breakdown: { "result_rule" => "correct_winner" })
    end

    user
  end

  # Same, as a member of the given group.
  def member_with(target_group, points:, exact: 0, in_tournament: nil)
    user_with_scores(points: points, exact: exact, in_tournament: in_tournament).tap do |user|
      create(:group_membership, group: target_group, user: user)
    end
  end


  # A GLOBAL (group_id NULL) snapshot row — the anchor the delta windows read.
  def global_anchor(user, points:, exact: 0, at: anchor_time, in_tournament: nil)
    create(:ranking_snapshot, user: user, tournament: in_tournament || tournament, group: nil,
                              points: points, exact_count: exact, snapshot_at: at)
  end

  def add_tournament_points(user, points, in_tournament: nil)
    tp = create(:tournament_prediction, user: user, tournament: in_tournament || tournament)
    create(:tournament_prediction_score, tournament_prediction: tp, points_champion: points)
  end

  def ranks_by_user(rows)
    rows.to_h { |row| [ row.user_id, row.rank_position ] }
  end

  describe "#call" do
    it "shares the rank position among ties (1, 1, 1, 4)" do
      tied = Array.new(3) { member_with(group, points: 10, exact: 2) }
      low = member_with(group, points: 5, exact: 1)

      ranks = ranks_by_user(described_class.new.call(tournament: tournament, group: group))

      expect(ranks.values_at(*tied.map(&:id))).to all(eq(1))
      expect(ranks[low.id]).to eq(4)
    end

    it "breaks point ties by exact_count" do
      more = member_with(group, points: 10, exact: 3)
      less = member_with(group, points: 10, exact: 1)

      ranks = ranks_by_user(described_class.new.call(tournament: tournament, group: group))

      expect(ranks[more.id]).to eq(1)
      expect(ranks[less.id]).to eq(2)
    end

    it "includes members with no scores at 0 points (day 1: everyone tied)" do
      members = Array.new(3) { member_with(group, points: 0) }

      rows = described_class.new.call(tournament: tournament, group: group)

      expect(rows.map(&:user_id)).to match_array(members.map(&:id))
      expect(rows.map(&:points)).to all(eq(0))
      expect(rows.map(&:rank_position)).to all(eq(1))
    end

    it "scopes the universe to the group's members" do
      other_group = create(:group, owner: create(:user))
      mine = member_with(group, points: 10)
      member_with(other_group, points: 99)

      rows = described_class.new.call(tournament: tournament, group: group)

      expect(rows.map(&:user_id)).to contain_exactly(mine.id)
    end

    it "adds tournament-prediction points to the match total" do
      user = member_with(group, points: 5)
      add_tournament_points(user, 50)

      row = described_class.new.call(tournament: tournament, group: group).find { |r| r.user_id == user.id }

      expect(row.points).to eq(55)
    end

    it "scopes points AND exact_count to the tournament (no cross-tournament mixing)" do
      other_tournament = create(:tournament)
      user = create(:user)
      create(:group_membership, group: group, user: user)
      # In the target tournament: 1 exact worth 5 points.
      in_t1 = create(:prediction, user: user, match: create(:match, tournament: tournament))
      create(:prediction_score, prediction: in_t1, points_result: 5, multiplier: 1.0,
                                breakdown: { "result_rule" => "exact_score" })
      add_tournament_points(user, 7) # tournament-prediction points in t1
      # In another tournament: must NOT count toward t1's leaderboard.
      in_t2 = create(:prediction, user: user, match: create(:match, tournament: other_tournament))
      create(:prediction_score, prediction: in_t2, points_result: 99, multiplier: 1.0,
                                breakdown: { "result_rule" => "exact_score" })
      add_tournament_points(user, 88, in_tournament: other_tournament)

      row = described_class.new.call(tournament: tournament, group: group).find { |r| r.user_id == user.id }

      expect(row.points).to eq(12)      # 5 (match) + 7 (tournament), NOT 99 or 88
      expect(row.exact_count).to eq(1)  # only t1's exact, not t2's
    end

    it "respects the limit while keeping the global rank" do
      5.times { |i| member_with(group, points: i + 1) }

      rows = described_class.new.call(tournament: tournament, group: group, limit: 2)

      expect(rows.size).to eq(2)
      expect(rows.map(&:rank_position)).to eq([ 1, 2 ])
    end

    it "returns every member with limit: nil (the snapshot-capture path, no truncation)" do
      members = Array.new(3) { |i| member_with(group, points: i + 1) }

      rows = described_class.new.call(tournament: tournament, group: group, limit: nil)

      expect(rows.size).to eq(3)
      expect(rows.map(&:user_id)).to match_array(members.map(&:id))
    end

    it "does not hit the database on a cache hit" do
      member_with(group, points: 5)
      cache = ActiveSupport::Cache::MemoryStore.new
      allow(Rails).to receive(:cache).and_return(cache)
      query = described_class.new
      query.call(tournament: tournament, group: group) # miss: populates the cache

      query_count = 0
      counter = lambda do |_n, _s, _f, _id, payload|
        query_count += 1 unless %w[SCHEMA TRANSACTION].include?(payload[:name])
      end
      ActiveSupport::Notifications.subscribed(counter, "sql.active_record") do
        expect(query.call(tournament: tournament, group: group)).to be_present # hit
      end

      expect(query_count).to eq(0)
    end
  end

  describe "delta windows (:today / :week)" do
    it ":today ranks by the delta since the anchor snapshot, not the cumulative total" do
      steady = user_with_scores(points: 20, exact: 2) # cumulative 20, anchored at 18 -> delta 2
      surger = user_with_scores(points: 10)           # cumulative 10, anchored at 3  -> delta 7
      global_anchor(steady, points: 18, exact: 2)
      global_anchor(surger, points: 3)

      rows = described_class.new.call(tournament: tournament, window: :today)

      expect(rows.map(&:user_id)).to eq([ surger.id, steady.id ]) # cumulative order would be the reverse
      expect(rows.map(&:points)).to eq([ 7, 2 ])
      expect(rows.map(&:rank_position)).to eq([ 1, 2 ])
      expect(rows.map(&:exact_count)).to eq([ 0, 0 ]) # exact_count is windowed too (2 - 2)
    end

    it "degrades to the cumulative total when no snapshot predates the window" do
      high = user_with_scores(points: 9)
      low = user_with_scores(points: 4)

      rows = described_class.new.call(tournament: tournament, window: :today)

      expect(rows.map(&:user_id)).to eq([ high.id, low.id ])
      expect(rows.map(&:points)).to eq([ 9, 4 ])
    end

    it ":week anchors strictly before the 7-day window start, skipping newer snapshots" do
      user = user_with_scores(points: 20)
      global_anchor(user, points: 4,  at: 10.days.ago)
      global_anchor(user, points: 12, at: 1.day.ago)

      today_row = described_class.new.call(tournament: tournament, window: :today).first
      week_row  = described_class.new.call(tournament: tournament, window: :week).first

      expect(today_row.points).to eq(8)  # 20 - 12: the latest snapshot before today
      expect(week_row.points).to eq(16)  # 20 - 4: the 1-day-old snapshot is INSIDE the week window
    end

    it "derives a group window from the GLOBAL anchor filtered to the members" do
      member = member_with(group, points: 10)
      outsider = user_with_scores(points: 50)
      global_anchor(member, points: 6) # a global row, NOT a for-group row
      global_anchor(outsider, points: 1)

      rows = described_class.new.call(tournament: tournament, group: group, window: :today)

      expect(rows.map(&:user_id)).to contain_exactly(member.id) # outsider filtered out
      expect(rows.first.points).to eq(4)                        # 10 - 6, baseline from the global anchor
    end

    it "does not mix tournaments in the window (scores nor anchors)" do
      other_tournament = create(:tournament)
      user = user_with_scores(points: 10)
      foreign = create(:prediction, user: user, match: create(:match, tournament: other_tournament))
      create(:prediction_score, prediction: foreign, points_result: 99, multiplier: 1.0,
                                breakdown: { "result_rule" => "exact_score" })
      global_anchor(user, points: 4)
      # A NEWER anchor in the other tournament: must not shadow t1's anchor.
      global_anchor(user, points: 9, at: 1.day.ago + 1.minute, in_tournament: other_tournament)

      row = described_class.new.call(tournament: tournament, window: :today).find { |r| r.user_id == user.id }

      expect(row.points).to eq(6) # 10 - 4: neither the 99 foreign points nor the foreign anchor leak
    end

    it "position_of ranks the user within the window (rank AND points are deltas)" do
      total_leader = user_with_scores(points: 30) # delta 1
      target = user_with_scores(points: 10)       # no anchor -> delta 10: window leader
      global_anchor(total_leader, points: 29)

      rows = described_class.new.position_of(target, tournament: tournament, window: :today)
      target_row = rows.find { |r| r.user_id == target.id }

      expect(target_row.rank_position).to eq(1) # would be 2 on cumulative points
      expect(target_row.points).to eq(10)
    end

    it "rejects an unknown window" do
      expect { described_class.new.call(tournament: tournament, window: :fortnight) }
        .to raise_error(ArgumentError, /unknown window/)
    end
  end

  describe "#position_of" do
    it "returns the user's row plus up to two neighbours each side" do
      members = [ 70, 60, 50, 40, 30, 20, 10 ].map { |p| member_with(group, points: p) }
      target = members[3] # 40 points -> rank 4

      rows = described_class.new.position_of(target, tournament: tournament, group: group)

      expect(rows.map(&:rank_position)).to eq([ 2, 3, 4, 5, 6 ])
      expect(rows.find { |r| r.user_id == target.id }.rank_position).to eq(4)
    end

    it "clamps the window at the top of the table" do
      members = [ 50, 40, 30, 20 ].map { |p| member_with(group, points: p) }
      leader = members.first # rank 1

      rows = described_class.new.position_of(leader, tournament: tournament, group: group)

      expect(rows.map(&:rank_position)).to eq([ 1, 2, 3 ])
    end

    it "returns an empty window when the user is outside the universe" do
      member_with(group, points: 5)
      outsider = create(:user)

      expect(described_class.new.position_of(outsider, tournament: tournament, group: group)).to eq([])
    end
  end
end
