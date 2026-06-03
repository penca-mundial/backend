require "rails_helper"

# These endpoints are implemented in later phases; Rack::Attack runs as
# middleware (before routing), so the throttle/blocklist behaviour is verified
# independently of the controllers.
RSpec.describe "Rack::Attack", :rack_attack, type: :request do
  let(:json_headers) { { "CONTENT_TYPE" => "application/json", "HTTP_USER_AGENT" => "rspec" } }

  def login(email: "user@example.com")
    post "/api/v1/auth/login", params: { email: }.to_json, headers: json_headers
  end

  describe "login throttle (5 / 5 min by IP + email)" do
    it "allows the first 5 attempts" do
      5.times { login }
      expect(response).not_to have_http_status(:too_many_requests)
    end

    it "returns 429 with Retry-After and a JSON error on the 6th attempt" do
      6.times { login }

      expect(response).to have_http_status(:too_many_requests)
      expect(response.headers["Retry-After"]).to be_present
      expect(response.parsed_body.dig("error", "code")).to eq("rate_limited")
    end
  end

  describe "signup throttle (3 / hour by IP)" do
    def signup
      post "/api/v1/auth/signup", params: {}.to_json, headers: json_headers
    end

    it "returns 429 on the 4th signup" do
      4.times { signup }
      expect(response).to have_http_status(:too_many_requests)
    end

    # A throttle configured for N requests must allow exactly N and trip on
    # N+1 — i.e. count each request once. This fails if Rack::Attack is ever
    # inserted into the middleware stack more than once and starts
    # double-counting (see the "middleware stack" regression below).
    it "allows the first 3 and throttles the 4th (counts each request once)" do
      3.times do
        signup
        expect(response).not_to have_http_status(:too_many_requests)
      end

      signup
      expect(response).to have_http_status(:too_many_requests)
    end
  end

  describe "missing User-Agent blocklist on auth endpoints" do
    it "blocks requests with a blank User-Agent" do
      post "/api/v1/auth/login",
        params: { email: "x@example.com" }.to_json,
        headers: { "CONTENT_TYPE" => "application/json", "HTTP_USER_AGENT" => "" }

      expect(response).to have_http_status(:forbidden)
    end
  end

  # Structural regression guard: rack-attack's railtie already inserts
  # Rack::Attack, so the app must NOT add it manually as well. A second insertion
  # is redundant config (only rack-attack's `rack.attack.called` re-entry guard
  # stops it from double-counting throttles); this spec fails if the duplicate
  # ever comes back.
  describe "middleware stack" do
    it "inserts Rack::Attack exactly once" do
      count = Rails.application.middleware.middlewares.count { |m| m == Rack::Attack }
      expect(count).to eq(1)
    end
  end
end
