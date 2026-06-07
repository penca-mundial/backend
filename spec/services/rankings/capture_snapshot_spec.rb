# frozen_string_literal: true

require "rails_helper"

RSpec.describe Rankings::CaptureSnapshot do
  let(:tournament) { create(:tournament) }
  let(:user_a) { create(:user) }
  let(:user_b) { create(:user) }

  def entry(user, points:, rank:, exact: 0)
    LeaderboardQuery::Row.new(
      user_id: user.id, username: user.username, avatar_url: nil,
      points: points, exact_count: exact, rank_position: rank
    )
  end

  # Stub LeaderboardQuery so the captured ranking is deterministic. Asserts the
  # service asks for the FULL set (limit: nil) for the right group.
  def stub_leaderboard(entries, group: nil)
    query = instance_double(LeaderboardQuery)
    allow(LeaderboardQuery).to receive(:new).and_return(query)
    allow(query).to receive(:call).with(hash_including(group: group, limit: nil)).and_return(entries)
  end

  describe "#call" do
    it "captures a global snapshot: one row per user, group_id NULL, tournament tagged" do
      stub_leaderboard([ entry(user_a, points: 30, rank: 1, exact: 2),
                         entry(user_b, points: 10, rank: 2) ])

      result = described_class.call(tournament: tournament, snapshot_at: Time.current)

      expect(result).to be_success
      expect(result.data).to eq(count: 2)
      rows = RankingSnapshot.all
      expect(rows.count).to eq(2)
      expect(rows.pluck(:group_id).uniq).to eq([ nil ])               # global
      expect(rows.pluck(:tournament_id).uniq).to eq([ tournament.id ])
      a = rows.find_by(user_id: user_a.id)
      expect(a).to have_attributes(points: 30, rank_position: 1, exact_count: 2)
    end

    it "captures a per-group snapshot with group_id set" do
      group = create(:group)
      stub_leaderboard([ entry(user_a, points: 5, rank: 1) ], group: group)

      described_class.call(tournament: tournament, group: group, snapshot_at: Time.current)

      expect(RankingSnapshot.where(group_id: group.id).count).to eq(1)
    end

    it "writes all rows in a single bulk upsert (no N+1)" do
      stub_leaderboard([ entry(user_a, points: 30, rank: 1), entry(user_b, points: 10, rank: 2) ])

      expect(RankingSnapshot).to receive(:upsert_all).once.and_call_original

      described_class.call(tournament: tournament, snapshot_at: Time.current)
    end

    it "returns success with count 0 and writes nothing for an empty leaderboard" do
      stub_leaderboard([])

      expect(RankingSnapshot).not_to receive(:upsert_all)
      result = described_class.call(tournament: tournament, snapshot_at: Time.current)

      expect(result).to be_success
      expect(result.data).to eq(count: 0)
      expect(RankingSnapshot.count).to eq(0)
    end

    describe "idempotency for the same snapshot_at" do
      it "does not duplicate the GLOBAL case (group_id NULL) on a re-run (NULLS NOT DISTINCT)" do
        at = Time.current
        stub_leaderboard([ entry(user_a, points: 30, rank: 1), entry(user_b, points: 10, rank: 2) ])

        described_class.call(tournament: tournament, snapshot_at: at)
        expect { described_class.call(tournament: tournament, snapshot_at: at) }
          .not_to change(RankingSnapshot, :count).from(2)
      end

      it "refreshes points/rank/exact on the conflicting row (upsert, not skip)" do
        at = Time.current
        stub_leaderboard([ entry(user_a, points: 10, rank: 2, exact: 0) ])
        described_class.call(tournament: tournament, snapshot_at: at)

        stub_leaderboard([ entry(user_a, points: 99, rank: 1, exact: 5) ]) # late correction
        described_class.call(tournament: tournament, snapshot_at: at)

        row = RankingSnapshot.find_by(user_id: user_a.id, group_id: nil, tournament_id: tournament.id)
        expect(row).to have_attributes(points: 99, rank_position: 1, exact_count: 5)
        expect(RankingSnapshot.count).to eq(1)
      end
    end

    it "does not mix snapshots across tournaments (same user/snapshot_at, different tournament)" do
      at = Time.current
      other = create(:tournament)
      stub_leaderboard([ entry(user_a, points: 30, rank: 1) ])
      described_class.call(tournament: tournament, snapshot_at: at)
      described_class.call(tournament: other, snapshot_at: at)

      expect(RankingSnapshot.where(user_id: user_a.id, group_id: nil).pluck(:tournament_id))
        .to contain_exactly(tournament.id, other.id)
    end
  end
end
