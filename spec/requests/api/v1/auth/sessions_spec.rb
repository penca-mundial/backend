# frozen_string_literal: true

require "rails_helper"

# rubocop:disable RSpec/DescribeClass
RSpec.describe "Api::V1::Auth::SessionsController", type: :request do
  # rubocop:enable RSpec/DescribeClass
  # Rack::Attack blocks blank User-Agent on /auth/*.
  let(:headers)  { { "User-Agent" => "rspec" } }
  let(:password) { "Sup3rSecret9" }
  let!(:user) do
    create(:user, email: "alice@example.com", password: password)
  end

  describe "POST /api/v1/auth/login" do
    it "returns 200 with the user payload and sets a session cookie" do
      post "/api/v1/auth/login",
           params: { email: user.email, password: password },
           headers: headers

      expect(response).to have_http_status(:ok)
      expect(response.parsed_body["user"]).to include(
        "email" => user.email, "username" => user.username
      )
      expect(response.parsed_body["user"]).not_to have_key("encrypted_password")
      expect(response.headers["Set-Cookie"]).to include("_penca_session")
    end

    it "returns 401 invalid_credentials for a wrong password" do
      post "/api/v1/auth/login",
           params: { email: user.email, password: "wrong-password-9" },
           headers: headers

      expect(response).to have_http_status(:unauthorized)
      expect(response.parsed_body.dig("error", "code")).to eq("invalid_credentials")
    end

    it "returns 401 invalid_credentials for a non-existent email (no email-existence leak)" do
      post "/api/v1/auth/login",
           params: { email: "ghost@example.com", password: password },
           headers: headers

      expect(response).to have_http_status(:unauthorized)
      expect(response.parsed_body.dig("error", "code")).to eq("invalid_credentials")
    end

    it "returns 401 email_not_confirmed for an unconfirmed user" do
      pending_user = create(:user, :unconfirmed, email: "pending@example.com", password: password)

      post "/api/v1/auth/login",
           params: { email: pending_user.email, password: password },
           headers: headers

      expect(response).to have_http_status(:unauthorized)
      expect(response.parsed_body.dig("error", "code")).to eq("email_not_confirmed")
    end

    it "returns 403 account_banned for a banned user" do
      banned = create(:user, :banned, email: "ban@example.com", password: password)

      post "/api/v1/auth/login",
           params: { email: banned.email, password: password },
           headers: headers

      expect(response).to have_http_status(:forbidden)
      expect(response.parsed_body.dig("error", "code")).to eq("account_banned")
    end

    it "returns 401 invalid_credentials for the system account even with a valid password" do
      system_user = create(:user, :system, password: password)

      post "/api/v1/auth/login",
           params: { email: system_user.email, password: password },
           headers: headers

      expect(response).to have_http_status(:unauthorized)
      expect(response.parsed_body.dig("error", "code")).to eq("invalid_credentials")
    end
  end

  describe "DELETE /api/v1/auth/logout" do
    it "returns 204 after logging in" do
      post "/api/v1/auth/login",
           params: { email: user.email, password: password },
           headers: headers
      expect(response).to have_http_status(:ok)

      delete "/api/v1/auth/logout", headers: headers

      expect(response).to have_http_status(:no_content)
      expect(response.body).to be_blank
    end

    it "returns 204 even without an active session" do
      delete "/api/v1/auth/logout", headers: headers

      expect(response).to have_http_status(:no_content)
    end
  end
end
