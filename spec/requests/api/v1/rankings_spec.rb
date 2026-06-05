# frozen_string_literal: true

require "rails_helper"

# rubocop:disable RSpec/DescribeClass
RSpec.describe "Api::V1::RankingsController", type: :request do
  # rubocop:enable RSpec/DescribeClass
  let(:user)    { create(:user) }
  let(:headers) { { "User-Agent" => "rspec" } }
  let(:group)   { create(:group, owner: create(:user)) }

  # Adds a member with the given match points / exact count (see LeaderboardQuery spec).
  def add_member(target_group, member, points: 0, exact: 0)
    create(:group_membership, group: target_group, user: member)
    exact.times do
      prediction = create(:prediction, user: member, match: create(:match))
      create(:prediction_score, prediction: prediction, points_result: 1, multiplier: 1.0,
                                breakdown: { "result_rule" => "exact_score" })
    end
    remaining = points - exact
    if remaining.positive?
      prediction = create(:prediction, user: member, match: create(:match))
      create(:prediction_score, prediction: prediction, points_result: remaining, multiplier: 1.0,
                                breakdown: { "result_rule" => "correct_winner" })
    end
    member
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

      it "clamps an absurd limit to the ceiling" do
        add_member(group, user, points: 5)

        get "/api/v1/rankings/groups/#{group.id}", params: { limit: 9999 }, headers: headers

        expect(response).to have_http_status(:ok)
        expect(response.parsed_body["entries"].size).to eq(1)
      end
    end
  end
end
