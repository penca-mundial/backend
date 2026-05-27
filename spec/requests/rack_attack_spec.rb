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
    it "returns 429 on the 4th signup" do
      4.times do
        post "/api/v1/auth/signup", params: {}.to_json, headers: json_headers
      end
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
end
