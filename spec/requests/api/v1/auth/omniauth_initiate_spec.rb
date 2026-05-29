# frozen_string_literal: true

require "rails_helper"

# rubocop:disable RSpec/DescribeClass
RSpec.describe "OmniAuth Google request phase", type: :request do
  # rubocop:enable RSpec/DescribeClass
  let(:headers) { { "User-Agent" => "rspec" } }

  # Exercise the REAL request phase (not OmniAuth test_mode) so the
  # omniauth-rails_csrf_protection guard actually runs. With
  # `request_validation_phase = nil` (see config/initializers/omniauth.rb) a
  # tokenless POST must pass straight through to the provider redirect.
  around do |example|
    original_test_mode = OmniAuth.config.test_mode
    OmniAuth.config.test_mode = false
    example.run
  ensure
    OmniAuth.config.test_mode = original_test_mode
  end

  it "redirects a tokenless POST to Google instead of the CSRF failure endpoint" do
    post "/users/auth/google_oauth2", headers: headers

    expect(response).to have_http_status(:found)
    expect(response.location).to start_with("https://accounts.google.com/")
    expect(response.location).not_to include("/users/auth/failure")
  end

  it "rejects GET on the initiate route (POST-only request phase)" do
    get "/users/auth/google_oauth2", headers: headers

    # OmniAuth only allows POST on the request phase; a GET never reaches the
    # provider redirect.
    expect(response.location.to_s).not_to start_with("https://accounts.google.com/")
  end
end
