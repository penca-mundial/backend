# frozen_string_literal: true

require "rails_helper"

# rubocop:disable RSpec/DescribeClass
RSpec.describe "GET /api/v1/auth/me", type: :request do
  # rubocop:enable RSpec/DescribeClass
  # Rack::Attack blocks blank User-Agent on /auth/*.
  let(:headers) { { "User-Agent" => "rspec" } }

  context "when authenticated" do
    let(:user) { create(:user, email: "alice@example.com", username: "alice_99") }

    before { login_as(user, scope: :user) }

    it "returns 200 with the user payload" do
      get "/api/v1/auth/me", headers: headers

      expect(response).to have_http_status(:ok)
      expect(response.parsed_body["user"]).to include(
        "id"       => user.id,
        "email"    => "alice@example.com",
        "username" => "alice_99"
      )
    end

    it "exposes needs_username: false when the user has a username" do
      get "/api/v1/auth/me", headers: headers

      expect(response.parsed_body["user"]["needs_username"]).to be(false)
    end

    it "does not leak credential or token columns" do
      get "/api/v1/auth/me", headers: headers

      payload = response.parsed_body["user"]
      expect(payload).not_to have_key("encrypted_password")
      expect(payload).not_to have_key("confirmation_token")
      expect(payload).not_to have_key("reset_password_token")
    end
  end

  context "when authenticated as an OAuth user without a username" do
    let(:user) do
      create(:user, :oauth, email: "bob@example.com", username: nil)
    end

    before { login_as(user, scope: :user) }

    it "returns 200 with needs_username: true" do
      get "/api/v1/auth/me", headers: headers

      expect(response).to have_http_status(:ok)
      expect(response.parsed_body["user"]).to include(
        "email"          => "bob@example.com",
        "username"       => nil,
        "needs_username" => true
      )
    end
  end

  context "when not authenticated" do
    it "returns 401 unauthenticated" do
      get "/api/v1/auth/me", headers: headers

      expect(response).to have_http_status(:unauthorized)
      expect(response.parsed_body.dig("error", "code")).to eq("unauthenticated")
    end
  end

  context "when the user is banned" do
    let(:user) { create(:user, :banned, email: "banned@example.com") }

    # Devise's Activatable hook tears down sessions for users whose
    # active_for_authentication? returns false. We stub it on this instance so
    # the request reaches our require_user! filter and exercises its 403
    # branch (the same branch a hand-rolled, Devise-bypassing auth path would
    # hit).
    before do
      allow(User).to receive(:find).with(user.id).and_return(user)
      allow(user).to receive(:active_for_authentication?).and_return(true)
      login_as(user, scope: :user)
    end

    it "returns 403 account_banned" do
      get "/api/v1/auth/me", headers: headers

      expect(response).to have_http_status(:forbidden)
      expect(response.parsed_body.dig("error", "code")).to eq("account_banned")
    end
  end
end
