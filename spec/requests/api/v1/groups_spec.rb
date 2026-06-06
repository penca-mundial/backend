# frozen_string_literal: true

require "rails_helper"

# rubocop:disable RSpec/DescribeClass
RSpec.describe "Api::V1::GroupsController", type: :request do
  # rubocop:enable RSpec/DescribeClass
  let(:user)    { create(:user) }
  let(:other)   { create(:user) }
  let(:headers) { { "User-Agent" => "rspec" } }

  # Mirrors Groups::CreateGroup: a group plus its owner's membership.
  def group_owned_by(owner, **attrs)
    group = create(:group, owner: owner, **attrs)
    create(:group_membership, group: group, user: owner)
    group
  end

  describe "GET /api/v1/groups/me" do
    it "returns 401 when unauthenticated" do
      get "/api/v1/groups/me", headers: headers
      expect(response).to have_http_status(:unauthorized)
    end

    context "when authenticated" do
      before { login_as(user, scope: :user) }

      it "lists the user's groups: general pool first, then by created_at desc" do
        older = group_owned_by(user)
        older.update_column(:created_at, 2.days.ago)
        newer = group_owned_by(user)
        newer.update_column(:created_at, 1.day.ago)
        pool = create(:group, :general_pool, owner: other)
        create(:group_membership, group: pool, user: user)

        get "/api/v1/groups/me", headers: headers

        expect(response).to have_http_status(:ok)
        expect(response.parsed_body.map { |g| g["id"] }).to eq([ pool.id, newer.id, older.id ])
        expect(response.parsed_body.first).to include("member_count", "is_owner", "code")
      end

      it "does not issue an N+1 for member_count" do
        3.times { group_owned_by(user) }

        query_count = 0
        counter = lambda do |_n, _s, _f, _id, payload|
          query_count += 1 unless %w[SCHEMA TRANSACTION].include?(payload[:name])
        end
        ActiveSupport::Notifications.subscribed(counter, "sql.active_record") do
          get "/api/v1/groups/me", headers: headers
        end

        expect(query_count).to be <= 5 # bounded, independent of the group count
      end
    end
  end

  describe "POST /api/v1/groups" do
    before { login_as(user, scope: :user) }

    it "creates a group and returns 201 with its code" do
      post "/api/v1/groups", params: { name: "Los Cracks" }.to_json,
                             headers: headers.merge("Content-Type" => "application/json")

      expect(response).to have_http_status(:created)
      expect(response.parsed_body).to include("name" => "Los Cracks", "is_owner" => true)
      expect(response.parsed_body["code"]).to match(/\A[A-Z0-9]{8}\z/)
    end

    it "returns 422 for an invalid name" do
      post "/api/v1/groups", params: { name: "ab" }.to_json,
                             headers: headers.merge("Content-Type" => "application/json")

      expect(response).to have_http_status(:unprocessable_content)
    end

    it "returns 422 when the owner is already at the group limit" do
      create_list(:group, Group::MAX_OWNED_GROUPS, owner: user)

      post "/api/v1/groups", params: { name: "Cuarto" }.to_json,
                             headers: headers.merge("Content-Type" => "application/json")

      expect(response).to have_http_status(:unprocessable_content)
      expect(response.parsed_body.dig("error", "message")).to match(/grupos activos/)
    end
  end

  describe "GET /api/v1/groups/:id" do
    before { login_as(user, scope: :user) }

    it "returns the group with member_count for a member" do
      group = group_owned_by(user)

      get "/api/v1/groups/#{group.id}", headers: headers

      expect(response).to have_http_status(:ok)
      expect(response.parsed_body).to include("id" => group.id, "member_count" => 1, "is_owner" => true)
    end

    it "returns 403 for a non-member" do
      group = group_owned_by(other)

      get "/api/v1/groups/#{group.id}", headers: headers

      expect(response).to have_http_status(:forbidden)
    end

    it "returns 404 for a non-existent group" do
      get "/api/v1/groups/0", headers: headers

      expect(response).to have_http_status(:not_found)
    end
  end

  describe "PATCH /api/v1/groups/:id" do
    before { login_as(user, scope: :user) }

    it "updates name/description for the owner" do
      group = group_owned_by(user)

      patch "/api/v1/groups/#{group.id}", params: { name: "Nuevo nombre" }.to_json,
                                          headers: headers.merge("Content-Type" => "application/json")

      expect(response).to have_http_status(:ok)
      expect(group.reload.name).to eq("Nuevo nombre")
    end

    it "returns 403 for a non-owner" do
      group = group_owned_by(other)
      create(:group_membership, group: group, user: user)

      patch "/api/v1/groups/#{group.id}", params: { name: "Hackeado" }.to_json,
                                          headers: headers.merge("Content-Type" => "application/json")

      expect(response).to have_http_status(:forbidden)
    end

    it "returns 422 for an invalid name" do
      group = group_owned_by(user)

      patch "/api/v1/groups/#{group.id}", params: { name: "ab" }.to_json,
                                          headers: headers.merge("Content-Type" => "application/json")

      expect(response).to have_http_status(:unprocessable_content)
    end

    it "updates only the description, leaving the name intact" do
      group = group_owned_by(user, name: "Nombre Fijo")

      patch "/api/v1/groups/#{group.id}", params: { description: "nueva desc" }.to_json,
                                          headers: headers.merge("Content-Type" => "application/json")

      expect(response).to have_http_status(:ok)
      expect(group.reload).to have_attributes(name: "Nombre Fijo", description: "nueva desc")
    end

    it "updates only the name, leaving the description intact" do
      group = group_owned_by(user, description: "desc original")

      patch "/api/v1/groups/#{group.id}", params: { name: "Nombre Nuevo" }.to_json,
                                          headers: headers.merge("Content-Type" => "application/json")

      expect(response).to have_http_status(:ok)
      expect(group.reload).to have_attributes(name: "Nombre Nuevo", description: "desc original")
    end
  end

  describe "DELETE /api/v1/groups/:id" do
    before { login_as(user, scope: :user) }

    it "soft-deletes the group for the owner (204)" do
      group = group_owned_by(user)

      delete "/api/v1/groups/#{group.id}", headers: headers

      expect(response).to have_http_status(:no_content)
      expect(group.reload.deleted_at).to be_present
    end

    it "returns 403 for a non-owner" do
      group = group_owned_by(other)
      create(:group_membership, group: group, user: user)

      delete "/api/v1/groups/#{group.id}", headers: headers

      expect(response).to have_http_status(:forbidden)
      expect(group.reload.deleted_at).to be_nil
    end
  end

  describe "POST /api/v1/groups/join" do
    before { login_as(user, scope: :user) }

    it "returns 201 when the user newly joins" do
      group = group_owned_by(other)

      post "/api/v1/groups/join", params: { code: group.code }.to_json,
                                  headers: headers.merge("Content-Type" => "application/json")

      expect(response).to have_http_status(:created)
      expect(group.reload.users).to include(user)
    end

    it "returns 200 when the user is already a member (idempotent)" do
      group = group_owned_by(other)
      create(:group_membership, group: group, user: user)

      post "/api/v1/groups/join", params: { code: group.code }.to_json,
                                  headers: headers.merge("Content-Type" => "application/json")

      expect(response).to have_http_status(:ok)
    end

    it "returns 422 for an invalid code" do
      post "/api/v1/groups/join", params: { code: "NOPE0000" }.to_json,
                                  headers: headers.merge("Content-Type" => "application/json")

      expect(response).to have_http_status(:unprocessable_content)
    end
  end

  describe "POST /api/v1/groups/:id/regenerate_code" do
    before { login_as(user, scope: :user) }

    it "rotates the code for the owner (200)" do
      group = group_owned_by(user)
      old_code = group.code

      post "/api/v1/groups/#{group.id}/regenerate_code", headers: headers

      expect(response).to have_http_status(:ok)
      expect(response.parsed_body["code"]).to match(/\A[A-Z0-9]{8}\z/)
      expect(response.parsed_body["code"]).not_to eq(old_code)
    end

    it "returns 403 for a non-owner" do
      group = group_owned_by(other)
      create(:group_membership, group: group, user: user)

      post "/api/v1/groups/#{group.id}/regenerate_code", headers: headers

      expect(response).to have_http_status(:forbidden)
    end
  end

  describe "GET /api/v1/groups/:id/members" do
    before { login_as(user, scope: :user) }

    it "returns a paginated member list for a member" do
      group = group_owned_by(user)
      create(:group_membership, group: group, user: other)

      get "/api/v1/groups/#{group.id}/members", headers: headers

      expect(response).to have_http_status(:ok)
      expect(response.headers["X-Total-Count"]).to eq("2")
      owner_row = response.parsed_body.find { |m| m["user"]["id"] == user.id }
      expect(owner_row).to include("joined_at", "is_owner" => true)
      expect(owner_row["user"]).to include("username")
      expect(owner_row["user"]).not_to include("email") # no credentials leaked
    end

    it "returns 403 for a non-member" do
      group = group_owned_by(other)

      get "/api/v1/groups/#{group.id}/members", headers: headers

      expect(response).to have_http_status(:forbidden)
    end
  end

  describe "DELETE /api/v1/groups/:id/members/:user_id" do
    before { login_as(user, scope: :user) }

    it "kicks a member for the owner (204)" do
      group = group_owned_by(user)
      create(:group_membership, group: group, user: other)

      delete "/api/v1/groups/#{group.id}/members/#{other.id}", headers: headers

      expect(response).to have_http_status(:no_content)
      expect(group.reload.users).not_to include(other)
    end

    it "returns 403 for a non-owner" do
      group = group_owned_by(other)
      create(:group_membership, group: group, user: user)

      delete "/api/v1/groups/#{group.id}/members/#{other.id}", headers: headers

      expect(response).to have_http_status(:forbidden)
    end

    it "returns 422 when the owner targets themselves" do
      group = group_owned_by(user)

      delete "/api/v1/groups/#{group.id}/members/#{user.id}", headers: headers

      expect(response).to have_http_status(:unprocessable_content)
    end

    it "returns 422 when the target is not a member" do
      group = group_owned_by(user)

      delete "/api/v1/groups/#{group.id}/members/#{other.id}", headers: headers

      expect(response).to have_http_status(:unprocessable_content)
    end
  end

  describe "owner_username (creator) exposure" do
    before { login_as(user, scope: :user) }

    def count_queries
      count = 0
      counter = lambda do |_n, _s, _f, _id, payload|
        count += 1 unless %w[SCHEMA TRANSACTION].include?(payload[:name])
      end
      ActiveSupport::Notifications.subscribed(counter, "sql.active_record") { yield }
      count
    end

    it "exposes the creator's username on show" do
      group = group_owned_by(other)
      create(:group_membership, group: group, user: user)

      get "/api/v1/groups/#{group.id}", headers: headers

      expect(response.parsed_body["owner_username"]).to eq(other.username)
    end

    it "exposes the creator's username for each group on /groups/me" do
      group = group_owned_by(other)
      create(:group_membership, group: group, user: user)

      get "/api/v1/groups/me", headers: headers

      expect(response.parsed_body.first).to include("owner_username" => other.username)
    end

    it "does not issue an N+1 for owner_username (bounded, independent of group count)" do
      6.times do
        g = group_owned_by(create(:user)) # 6 groups, each owned by a DISTINCT user
        create(:group_membership, group: g, user: user)
      end

      query_count = count_queries { get "/api/v1/groups/me", headers: headers }

      # With :owner preloaded the owners load in one query; without it this would
      # be ~6 extra (one per distinct owner). Bounded well below the per-group count.
      expect(response.parsed_body.size).to eq(6)
      expect(query_count).to be <= 6
    end
  end
end
