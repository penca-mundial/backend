# frozen_string_literal: true

require "rails_helper"

# rubocop:disable RSpec/DescribeClass
RSpec.describe "Api::V1::Auth::PasswordsController", type: :request do
  # rubocop:enable RSpec/DescribeClass
  include ActiveJob::TestHelper

  let(:headers) { { "User-Agent" => "rspec" } }

  def user_with_token(reset_password_sent_at: Time.current, email: "alice@example.com")
    user = create(:user, email: email)
    raw, digest = Devise.token_generator.generate(User, :reset_password_token)
    user.update_columns(reset_password_token: digest,
                        reset_password_sent_at: reset_password_sent_at)
    [ user, raw ]
  end

  describe "POST /api/v1/auth/password" do
    it "returns 202 and sends the reset email for a registered address" do
      user = create(:user, email: "alice@example.com")
      ActionMailer::Base.deliveries.clear

      perform_enqueued_jobs do
        post "/api/v1/auth/password", params: { email: user.email }, headers: headers
      end

      expect(response).to have_http_status(:accepted)
      expect(ActionMailer::Base.deliveries.last.to).to eq([ user.email ])
    end

    it "returns 202 even for an unregistered address (anti-enumeration)" do
      post "/api/v1/auth/password",
           params: { email: "ghost@example.com" }, headers: headers

      expect(response).to have_http_status(:accepted)
    end
  end

  describe "PUT /api/v1/auth/password" do
    it "returns 200 with the user payload and updates the password for a valid token" do
      user, raw = user_with_token

      put "/api/v1/auth/password",
          params: { reset_password_token: raw, password: "BrandN3wPass" },
          headers: headers

      expect(response).to have_http_status(:ok)
      expect(response.parsed_body["user"]).to include("email" => user.email)
      expect(user.reload.valid_password?("BrandN3wPass")).to be true
    end

    it "returns 400 token_invalid for a token that matches no user" do
      put "/api/v1/auth/password",
          params: { reset_password_token: "bogus", password: "BrandN3wPass" },
          headers: headers

      expect(response).to have_http_status(:bad_request)
      expect(response.parsed_body.dig("error", "code")).to eq("token_invalid")
    end

    it "returns 400 token_expired when the token is older than reset_password_within" do
      _user, raw = user_with_token(reset_password_sent_at: 7.hours.ago)

      put "/api/v1/auth/password",
          params: { reset_password_token: raw, password: "BrandN3wPass" },
          headers: headers

      expect(response).to have_http_status(:bad_request)
      expect(response.parsed_body.dig("error", "code")).to eq("token_expired")
    end

    it "returns 422 validation_error for a weak password" do
      _user, raw = user_with_token

      put "/api/v1/auth/password",
          params: { reset_password_token: raw, password: "WeakPasswordNoDigit" },
          headers: headers

      expect(response).to have_http_status(:unprocessable_content)
      expect(response.parsed_body.dig("error", "code")).to eq("validation_error")
    end
  end

  # Confirms the namespace-wide CSRF skip (ApiCsrfHandling in BaseController)
  # covers this controller too. Test env disables forgery protection, so flip
  # it on to match dev/prod.
  describe "with forgery protection enabled (dev/prod parity)" do
    around do |example|
      original = Api::V1::BaseController.allow_forgery_protection
      Api::V1::BaseController.allow_forgery_protection = true
      example.run
      Api::V1::BaseController.allow_forgery_protection = original
    end

    it "accepts the reset request without an authenticity_token instead of raising" do
      user = create(:user, email: "alice@example.com")

      post "/api/v1/auth/password", params: { email: user.email }, headers: headers

      expect(response).to have_http_status(:accepted)
    end
  end
end
