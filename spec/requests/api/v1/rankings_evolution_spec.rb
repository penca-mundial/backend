# frozen_string_literal: true

require "rails_helper"

# rubocop:disable RSpec/DescribeClass
RSpec.describe "GET /api/v1/rankings/groups/:id/evolution", type: :request do
  # rubocop:enable RSpec/DescribeClass
  include ActiveSupport::Testing::TimeHelpers

  let(:headers) { { "User-Agent" => "rspec" } }
  let(:tournament) { create(:tournament) } # the sole tournament -> "current"
  let(:owner) { create(:user) }
  let(:group) { create(:group, owner: owner) }
  let(:user) { create(:user) }

  def join(member)
    create(:group_membership, group: group, user: member)
  end

  def open_the_gate!
    create_list(:match, GroupEvolutionQuery::MIN_FINISHED_MATCHES, :finished, tournament: tournament)
  end

  def snapshot(member, day:, points:, exact: 0)
    create(:ranking_snapshot, user: member, tournament: tournament, group: nil,
                              snapshot_at: day.to_time(:utc), points: points, exact_count: exact, rank_position: 1)
  end

  it "returns 401 when unauthenticated" do
    get "/api/v1/rankings/groups/#{group.id}/evolution", headers: headers

    expect(response).to have_http_status(:unauthorized)
  end

  context "when authenticated" do
    before { login_as(user, scope: :user) }

    it "returns 403 when the current user is not a member" do
      join(create(:user)) # someone else is in the group

      get "/api/v1/rankings/groups/#{group.id}/evolution", headers: headers

      expect(response).to have_http_status(:forbidden)
    end

    it "returns 404 when the group does not exist" do
      get "/api/v1/rankings/groups/0/evolution", headers: headers

      expect(response).to have_http_status(:not_found)
    end

    it "reports available:false before the 5-match gate (empty lines)" do
      join(user)
      create_list(:match, 4, :finished, tournament: tournament)

      get "/api/v1/rankings/groups/#{group.id}/evolution", headers: headers

      expect(response).to have_http_status(:ok)
      expect(response.parsed_body).to eq("available" => false, "lines" => [])
    end

    it "returns the line-set with each user's date/points/rank series" do
      join(user)
      rival = create(:user, username: "rival_one")
      join(rival)
      open_the_gate!
      d1 = Date.new(2026, 6, 1)
      d2 = Date.new(2026, 6, 2)
      snapshot(user,  day: d1, points: 10)
      snapshot(rival, day: d1, points: 5)
      snapshot(user,  day: d2, points: 12)
      snapshot(rival, day: d2, points: 20)

      get "/api/v1/rankings/groups/#{group.id}/evolution", headers: headers

      body = response.parsed_body
      expect(body["available"]).to be(true)

      mine = body["lines"].find { |line| line.dig("user", "id") == user.id }
      expect(mine["user"].keys).to contain_exactly("id", "username", "avatar_url")
      expect(mine["user"]["id"]).to be_a(Integer) # realistic numeric ids (ADR 0004)
      expect(mine["series"]).to eq([
        { "date" => "2026-06-01", "points" => 10, "rank" => 1 },
        { "date" => "2026-06-02", "points" => 12, "rank" => 2 }
      ])
    end

    it "caches the body within the short TTL and recomputes after it expires" do
      # The test env uses a null_store, so swap in a real store to exercise the TTL.
      cache = ActiveSupport::Cache::MemoryStore.new
      allow(Rails).to receive(:cache).and_return(cache)
      join(user)
      open_the_gate!
      snapshot(user, day: Date.new(2026, 6, 1), points: 10)

      allow(GroupEvolutionQuery).to receive(:call).and_call_original

      get "/api/v1/rankings/groups/#{group.id}/evolution", headers: headers
      get "/api/v1/rankings/groups/#{group.id}/evolution", headers: headers
      expect(GroupEvolutionQuery).to have_received(:call).once

      travel(Api::V1::RankingsController::EVOLUTION_CACHE_TTL + 1.second) do
        get "/api/v1/rankings/groups/#{group.id}/evolution", headers: headers
      end
      expect(GroupEvolutionQuery).to have_received(:call).twice
    end
  end
end
