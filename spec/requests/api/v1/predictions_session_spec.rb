# frozen_string_literal: true

require "rails_helper"

# Reproduces the production bug where an authenticated cookie session works for
# GET /api/v1/predictions/me but the PUT /api/v1/predictions write returns 401.
#
# Unlike the other predictions specs, this one does NOT use `login_as` (Warden
# test mode injects the user directly and bypasses the real session fetch, which
# is exactly why the existing green suite never caught this). Here we log in
# through the real endpoint so the `_penca_session` cookie round-trips and the
# real middleware ordering applies.
#
# rubocop:disable RSpec/DescribeClass
RSpec.describe "Api::V1::PredictionsController cookie session", type: :request do
  # rubocop:enable RSpec/DescribeClass
  let(:headers)  { { "User-Agent" => "rspec" } }
  let(:user)     { create(:user, password: "Sup3rSecret") }
  let(:upcoming) { create(:match, kickoff_at: 1.week.from_now) }

  # Use the real authentication path (no Warden test-mode shortcut) so the bug
  # can manifest the way it does in the browser.
  before { Warden.test_reset! }

  # Rack::Attack is disabled by default in specs; the bug only manifests when
  # its `predictions` throttle (which reads Warden) actually runs, so enable it.
  it "keeps the same cookie session authenticated across GET and PUT", :rack_attack do
    post "/api/v1/auth/login",
      params: { email: user.email, password: "Sup3rSecret" }.to_json,
      headers: headers.merge("Content-Type" => "application/json")
    expect(response).to have_http_status(:ok)

    # GET on the same session succeeds.
    get "/api/v1/predictions/me", headers: headers
    expect(response).to have_http_status(:ok)

    # The write on the SAME session must also succeed.
    put "/api/v1/predictions",
      params: { match_id: upcoming.id, predicted_home_score: 2, predicted_away_score: 1 }.to_json,
      headers: headers.merge("Content-Type" => "application/json")

    expect(response).to have_http_status(:ok)
  end
end
