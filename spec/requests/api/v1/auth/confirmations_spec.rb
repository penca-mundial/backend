# frozen_string_literal: true

require "rails_helper"

# rubocop:disable RSpec/DescribeClass
RSpec.describe "Api::V1::Auth::ConfirmationsController", type: :request do
  # rubocop:enable RSpec/DescribeClass
  let(:headers) { { "User-Agent" => "rspec" } }

  def unconfirmed_with_token(confirmation_sent_at: Time.current, email: "alice@example.com")
    user = create(:user, :unconfirmed, email: email)
    raw, digest = Devise.token_generator.generate(User, :confirmation_token)
    user.update_columns(confirmation_token: digest, confirmation_sent_at: confirmation_sent_at)
    [ user, raw ]
  end

  describe "GET /api/v1/auth/confirmation" do
    it "confirms the user and redirects to the SPA with status=success" do
      user, raw = unconfirmed_with_token

      get "/api/v1/auth/confirmation", params: { confirmation_token: raw }, headers: headers

      expect(response).to have_http_status(:redirect)
      expect(response.location).to match(%r{/confirm-email\?status=success\z})
      expect(user.reload.confirmed_at).to be_present
    end

    it "redirects with status=invalid for a token that matches no user" do
      get "/api/v1/auth/confirmation", params: { confirmation_token: "bogus" }, headers: headers

      expect(response).to have_http_status(:redirect)
      expect(response.location).to match(%r{/confirm-email\?status=invalid\z})
    end

    it "redirects with status=expired when the token is older than confirm_within" do
      _user, raw = unconfirmed_with_token(confirmation_sent_at: 2.days.ago)

      get "/api/v1/auth/confirmation", params: { confirmation_token: raw }, headers: headers

      expect(response).to have_http_status(:redirect)
      expect(response.location).to match(%r{/confirm-email\?status=expired\z})
    end
  end

  describe "POST /api/v1/auth/confirmation" do
    it "returns 202 and sends the confirmation email for an unconfirmed user" do
      user = create(:user, :unconfirmed, email: "pending@example.com")
      ActionMailer::Base.deliveries.clear

      post "/api/v1/auth/confirmation", params: { email: user.email }, headers: headers

      expect(response).to have_http_status(:accepted)
      expect(ActionMailer::Base.deliveries.last.to).to eq([ user.email ])
    end

    it "returns 202 even when no user matches (anti-enumeration)" do
      post "/api/v1/auth/confirmation",
           params: { email: "ghost@example.com" }, headers: headers

      expect(response).to have_http_status(:accepted)
    end
  end
end
