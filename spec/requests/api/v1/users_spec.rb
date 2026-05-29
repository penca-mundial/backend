# frozen_string_literal: true

require "rails_helper"

# rubocop:disable RSpec/DescribeClass
RSpec.describe "Api::V1::UsersController", type: :request do
  # rubocop:enable RSpec/DescribeClass
  let(:headers) { { "User-Agent" => "rspec" } }

  describe "PATCH /api/v1/users/me" do
    let(:user) do
      create(:user,
             email: "alice@example.com", username: "alice_99",
             timezone: "UTC", avatar_url: nil)
    end

    context "when not authenticated" do
      it "returns 401" do
        patch "/api/v1/users/me", params: { timezone: "America/Montevideo" }, headers: headers
        expect(response).to have_http_status(:unauthorized)
      end
    end

    context "when authenticated" do
      before { login_as(user, scope: :user) }

      it "updates the timezone" do
        patch "/api/v1/users/me",
              params: { timezone: "America/Montevideo" }, headers: headers

        expect(response).to have_http_status(:ok)
        expect(response.parsed_body["user"]).to include("timezone" => "America/Montevideo")
        expect(user.reload.timezone).to eq("America/Montevideo")
      end

      it "updates the avatar_url" do
        patch "/api/v1/users/me",
              params: { avatar_url: "https://cdn.example.com/a.png" }, headers: headers

        expect(response).to have_http_status(:ok)
        expect(user.reload.avatar_url).to eq("https://cdn.example.com/a.png")
      end

      it "changes the username, lowercasing it" do
        patch "/api/v1/users/me", params: { username: "Alice_New" }, headers: headers

        expect(response).to have_http_status(:ok)
        expect(response.parsed_body["user"]).to include("username" => "alice_new")
        expect(user.reload.username).to eq("alice_new")
      end

      it "rejects a duplicate username (case-insensitive) with 422" do
        create(:user, username: "taken_name")

        patch "/api/v1/users/me", params: { username: "Taken_Name" }, headers: headers

        expect(response).to have_http_status(:unprocessable_content)
        expect(response.parsed_body.dig("error", "code")).to eq("validation_error")
        expect(response.parsed_body.dig("error", "details", "errors").join).to match(/[Uu]sername/)
      end

      it "rejects an invalid username with 422" do
        patch "/api/v1/users/me", params: { username: "ab" }, headers: headers

        expect(response).to have_http_status(:unprocessable_content)
        expect(response.parsed_body.dig("error", "code")).to eq("validation_error")
      end

      it "ignores attempts to change email" do
        patch "/api/v1/users/me",
              params: { email: "hacker@example.com" }, headers: headers

        expect(response).to have_http_status(:ok)
        expect(user.reload.email).to eq("alice@example.com")
      end

      it "ignores attempts to change admin" do
        patch "/api/v1/users/me", params: { admin: true }, headers: headers

        expect(response).to have_http_status(:ok)
        expect(user.reload.admin).to be(false)
      end

      it "ignores attempts to change system" do
        patch "/api/v1/users/me", params: { system: true }, headers: headers

        expect(response).to have_http_status(:ok)
        expect(user.reload.system).to be(false)
      end

      it "ignores attempts to set banned_at" do
        patch "/api/v1/users/me",
              params: { banned_at: nil, timezone: "UTC" }, headers: headers

        expect(response).to have_http_status(:ok)
        expect(user.reload.banned_at).to be_nil
      end
    end
  end

  describe "POST /api/v1/users/me/username" do
    context "when not authenticated" do
      it "returns 401" do
        post "/api/v1/users/me/username", params: { username: "bob_99" }, headers: headers
        expect(response).to have_http_status(:unauthorized)
      end
    end

    context "when the user has no username yet (post-Google flow)" do
      let(:user) { create(:user, :oauth, username: nil) }

      before { login_as(user, scope: :user) }

      it "sets the username and returns 200" do
        post "/api/v1/users/me/username",
             params: { username: "bob_99" }, headers: headers

        expect(response).to have_http_status(:ok)
        expect(response.parsed_body["user"]).to include("username" => "bob_99")
        expect(user.reload.username).to eq("bob_99")
      end

      it "lowercases the username" do
        post "/api/v1/users/me/username",
             params: { username: "BOB_99" }, headers: headers

        expect(response).to have_http_status(:ok)
        expect(user.reload.username).to eq("bob_99")
      end

      it "returns 422 when the username is invalid" do
        post "/api/v1/users/me/username",
             params: { username: "no" }, headers: headers

        expect(response).to have_http_status(:unprocessable_content)
        expect(response.parsed_body.dig("error", "code")).to eq("validation_error")
      end

      it "returns 422 when the username is already taken" do
        create(:user, username: "taken_name")

        post "/api/v1/users/me/username",
             params: { username: "Taken_Name" }, headers: headers

        expect(response).to have_http_status(:unprocessable_content)
        expect(response.parsed_body.dig("error", "details", "errors").join).to match(/[Uu]sername/)
      end
    end

    context "when the user already has a username" do
      let(:user) { create(:user, username: "alice_99") }

      before { login_as(user, scope: :user) }

      it "returns 409 username_already_set without changing it" do
        post "/api/v1/users/me/username",
             params: { username: "new_name" }, headers: headers

        expect(response).to have_http_status(:conflict)
        expect(response.parsed_body.dig("error", "code")).to eq("username_already_set")
        expect(user.reload.username).to eq("alice_99")
      end
    end
  end
end
