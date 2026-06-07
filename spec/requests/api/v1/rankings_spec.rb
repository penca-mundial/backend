# frozen_string_literal: true

require "rails_helper"

# rubocop:disable RSpec/DescribeClass
RSpec.describe "Api::V1::RankingsController", type: :request do
  # rubocop:enable RSpec/DescribeClass
  let(:user)    { create(:user) }
  # The GLOBAL (group_id NULL) anchor snapshot the delta windows subtract. Rows
  # of one capture share snapshot_at (see RankingSnapshotJob), so the helper
  # pins a single shared timestamp.
  let(:anchor_time) { 1.day.ago }
  let(:headers) { { "User-Agent" => "rspec" } }
  let(:group)   { create(:group, owner: create(:user)) }
  # The sole tournament, so CurrentTournamentQuery (resolved by the controller)
  # returns it and the scoped leaderboard counts the scores created below.
  let(:tournament) { create(:tournament) }

  # Gives a user the given match points / exact count (see LeaderboardQuery spec).
  # No membership — the global universe.
  def add_scores(member, points: 0, exact: 0)
    exact.times do
      prediction = create(:prediction, user: member, match: create(:match, tournament: tournament))
      create(:prediction_score, prediction: prediction, points_result: 1, multiplier: 1.0,
                                breakdown: { "result_rule" => "exact_score" })
    end
    remaining = points - exact
    if remaining.positive?
      prediction = create(:prediction, user: member, match: create(:match, tournament: tournament))
      create(:prediction_score, prediction: prediction, points_result: remaining, multiplier: 1.0,
                                breakdown: { "result_rule" => "correct_winner" })
    end
    member
  end

  # Same, as a member of the given group.
  def add_member(target_group, member, points: 0, exact: 0)
    create(:group_membership, group: target_group, user: member)
    add_scores(member, points: points, exact: exact)
  end


  def global_anchor(member, points:, at: anchor_time)
    create(:ranking_snapshot, user: member, tournament: tournament, group: nil,
                              points: points, snapshot_at: at)
  end

  describe "GET /api/v1/rankings/global" do
    it "returns 401 when unauthenticated" do
      get "/api/v1/rankings/global", headers: headers

      expect(response).to have_http_status(:unauthorized)
    end

    context "when authenticated" do
      before { login_as(user, scope: :user) }

      it "ranks every user with shared positions on ties — no membership required" do
        add_scores(user, points: 10)
        add_scores(create(:user), points: 10)
        add_scores(create(:user), points: 5)

        get "/api/v1/rankings/global", headers: headers

        expect(response).to have_http_status(:ok)
        entries = response.parsed_body["entries"]
        expect(entries.size).to eq(3)
        expect(entries.map { |e| e["rank_position"] }).to eq([ 1, 1, 3 ])
        expect(response.parsed_body["me"]).to be_nil
      end

      it "returns window deltas (not cumulative points) with window=today, and total stays cumulative" do
        rival = create(:user)
        add_scores(user, points: 20)  # anchored at 18 -> today delta 2
        add_scores(rival, points: 10) # anchored at 3  -> today delta 7
        global_anchor(user, points: 18)
        global_anchor(rival, points: 3)

        get "/api/v1/rankings/global", params: { window: "today" }, headers: headers
        today_entries = response.parsed_body["entries"]

        get "/api/v1/rankings/global", params: { window: "total" }, headers: headers
        total_entries = response.parsed_body["entries"]

        expect(today_entries.map { |e| [ e["user_id"], e["points"] ] }).to eq([ [ rival.id, 7 ], [ user.id, 2 ] ])
        expect(total_entries.map { |e| [ e["user_id"], e["points"] ] }).to eq([ [ user.id, 20 ], [ rival.id, 10 ] ])
      end

      it "returns me with the window's rank and points even outside the top-N" do
        rival = create(:user)
        add_scores(user, points: 20)  # anchored at 18 -> today delta 2: SECOND in the window
        add_scores(rival, points: 10) # no anchor      -> today delta 10: window leader
        global_anchor(user, points: 18)

        get "/api/v1/rankings/global", params: { window: "today", limit: 1, include_me: "true" },
                                       headers: headers

        expect(response).to have_http_status(:ok)
        expect(response.parsed_body["entries"].map { |e| e["user_id"] }).to eq([ rival.id ]) # top-1 only
        my_row = response.parsed_body["me"].find { |e| e["user_id"] == user.id }
        expect(my_row).to include("rank_position" => 2, "points" => 2)
      end

      it "falls back to total on an unknown window" do
        add_scores(user, points: 20)
        global_anchor(user, points: 18)

        get "/api/v1/rankings/global", params: { window: "fortnight" }, headers: headers

        expect(response).to have_http_status(:ok)
        expect(response.parsed_body["entries"].first["points"]).to eq(20) # cumulative, not the delta 2
      end

      it "returns 404 when there is no tournament at all" do
        get "/api/v1/rankings/global", headers: headers

        expect(response).to have_http_status(:not_found)
      end
    end
  end

  describe "GET /api/v1/rankings/groups/:id" do
    it "returns 401 when unauthenticated" do
      get "/api/v1/rankings/groups/#{group.id}", headers: headers

      expect(response).to have_http_status(:unauthorized)
    end

    context "when authenticated" do
      before { login_as(user, scope: :user) }

      it "returns the ranked entries with shared positions on ties; me is null" do
        add_member(group, user, points: 10)
        add_member(group, create(:user), points: 10)
        add_member(group, create(:user), points: 5)

        get "/api/v1/rankings/groups/#{group.id}", headers: headers

        expect(response).to have_http_status(:ok)
        entries = response.parsed_body["entries"]
        expect(entries.size).to eq(3)
        expect(entries.map { |e| e["rank_position"] }).to eq([ 1, 1, 3 ])
        expect(entries.first).to include(
          "user_id", "username", "avatar_url", "points", "exact_count", "rank_position"
        )
        expect(response.parsed_body["me"]).to be_nil
      end

      it "adds me (the user's row plus neighbours) when include_me is truthy" do
        add_member(group, user, points: 10) # lowest
        4.times { |i| add_member(group, create(:user), points: 100 + i) }

        get "/api/v1/rankings/groups/#{group.id}", params: { include_me: "true" }, headers: headers

        expect(response).to have_http_status(:ok)
        me = response.parsed_body["me"]
        expect(me).to be_an(Array)
        expect(me.map { |e| e["user_id"] }).to include(user.id)
      end

      it "returns 403 when the current user is not a member" do
        add_member(group, create(:user), points: 5) # someone else is in the group

        get "/api/v1/rankings/groups/#{group.id}", headers: headers

        expect(response).to have_http_status(:forbidden)
      end

      it "returns 404 when the group does not exist" do
        get "/api/v1/rankings/groups/0", headers: headers

        expect(response).to have_http_status(:not_found)
      end

      it "applies the window to the group leaderboard, deriving from the global anchor" do
        add_member(group, user, points: 20)
        global_anchor(user, points: 15) # global row — for-group snapshot rows do not exist

        get "/api/v1/rankings/groups/#{group.id}", params: { window: "today" }, headers: headers

        expect(response).to have_http_status(:ok)
        expect(response.parsed_body["entries"].first["points"]).to eq(5) # 20 - 15
      end

      it "clamps an absurd limit to the ceiling" do
        add_member(group, user, points: 5)

        get "/api/v1/rankings/groups/#{group.id}", params: { limit: 9999 }, headers: headers

        expect(response).to have_http_status(:ok)
        expect(response.parsed_body["entries"].size).to eq(1)
      end
    end
  end
end
