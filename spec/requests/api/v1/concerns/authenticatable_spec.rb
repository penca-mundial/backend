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
    login_as(FakeUser.new(id: 42, admin: false, banned_at: nil), scope: :user)
    get "/api/v1/auth_probes/show"
    expect(response).to have_http_status(:ok)
    expect(response.parsed_body).to eq("user_id" => 42)
  end

  it "returns 403 account_banned for a banned user" do
    login_as(FakeUser.new(id: 7, admin: false, banned_at: Time.current), scope: :user)
    get "/api/v1/auth_probes/show"
    expect(response).to have_http_status(:forbidden)
    expect(response.parsed_body.dig("error", "code")).to eq("account_banned")
  end
end
