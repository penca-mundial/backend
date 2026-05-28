require "rails_helper"

module Api
  module V1
    class AuthProbesController < BaseController
      def show
        render json: { user_id: current_user.id }
      end
    end
  end
end

RSpec.describe "Authenticatable", type: :request do
  before(:all) do # rubocop:disable RSpec/BeforeAfterAll
    Rails.application.routes.draw do
      namespace :api do
        namespace :v1 do
          get "auth_probes/show", to: "auth_probes#show"
        end
      end
    end
  end

  after(:all) { Rails.application.reload_routes! } # rubocop:disable RSpec/BeforeAfterAll

  it "returns 401 without a session" do
    get "/api/v1/auth_probes/show"
    expect(response).to have_http_status(:unauthorized)
    expect(response.parsed_body.dig("error", "code")).to eq("unauthenticated")
  end

  it "allows an authenticated, non-banned user" do
    user = create(:user)
    login_as(user, scope: :user)
    get "/api/v1/auth_probes/show"
    expect(response).to have_http_status(:ok)
    expect(response.parsed_body).to eq("user_id" => user.id)
  end

  it "rejects a user who is banned after login (Devise drops the session, 401)" do
    user = create(:user)
    login_as(user, scope: :user)
    # Banning the user invalidates the session: Devise's active_for_authentication?
    # returns false, the fetch hook logs them out, the next request comes in
    # unauthenticated. The concern's banned → 403 branch is defensive cover
    # for cases where a stale session somehow slips past Devise.
    user.update!(banned_at: Time.current)

    get "/api/v1/auth_probes/show"

    expect(response).to have_http_status(:unauthorized)
  end
end
