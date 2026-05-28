# frozen_string_literal: true

require "rails_helper"

# rubocop:disable RSpec/DescribeClass
RSpec.describe "Api::V1::Auth::OmniauthCallbacksController", type: :request do
  # rubocop:enable RSpec/DescribeClass
  let(:headers) { { "User-Agent" => "rspec" } }

  # OmniAuth's request-phase URL is normally POST-only (the
  # omniauth-rails_csrf_protection gem enforces that), which doesn't survive
  # request specs without a real CSRF token. Allowing GET for tests lets us
  # walk the full middleware → routing path the same way a real browser hits
  # the callback.
  around do |example|
    original_methods = OmniAuth.config.allowed_request_methods
    original_silence = OmniAuth.config.silence_get_warning
    OmniAuth.config.test_mode = true
    OmniAuth.config.allowed_request_methods = %i[get post]
    OmniAuth.config.silence_get_warning = true
    begin
      example.run
    ensure
      OmniAuth.config.allowed_request_methods = original_methods
      OmniAuth.config.silence_get_warning = original_silence
      OmniAuth.config.mock_auth[:google_oauth2] = nil
      OmniAuth.config.test_mode = false
    end
  end

  def mock_google(uid: "google-uid-1", email: "alice@example.com", image: "https://img/alice.png")
    OmniAuth.config.mock_auth[:google_oauth2] = OmniAuth::AuthHash.new(
      provider: "google_oauth2",
      uid:      uid,
      info:     { email: email, name: "Alice", image: image }
    )
  end

  # Run the request phase (which OmniAuth's test_mode redirects straight to
  # /users/auth/google_oauth2/callback) and let it land on our controller.
  def google_callback!
    get "/users/auth/google_oauth2", headers: headers
    follow_redirect!
  end

  describe "first-time Google login" do
    it "creates the user, sets the session cookie, and redirects with needs_username=true" do
      mock_google
      expect { google_callback! }.to change(User, :count).by(1)

      expect(response).to have_http_status(:redirect)
      expect(response.location).to match(%r{/auth/google/callback\?needs_username=true\z})
      expect(response.headers["Set-Cookie"]).to include("_penca_session")

      user = User.find_by!(email: "alice@example.com")
      expect(user.provider).to eq("google_oauth2")
      expect(user.confirmed_at).to be_present
      expect(user.username).to be_nil
    end
  end

  describe "returning Google user" do
    it "re-uses the user and reports needs_username=false once they have one" do
      mock_google
      google_callback!
      user = User.find_by!(provider: "google_oauth2", uid: "google-uid-1")
      user.update!(username: "alice_99")

      expect { google_callback! }.not_to change(User, :count)

      expect(response.location).to match(%r{/auth/google/callback\?needs_username=false\z})
    end
  end

  describe "email belongs to a password user" do
    it "redirects to /login with error=use_password" do
      create(:user, email: "alice@example.com", provider: nil)
      mock_google

      google_callback!

      expect(response).to have_http_status(:redirect)
      expect(response.location).to match(%r{/login\?error=use_password\z})
    end
  end
end
