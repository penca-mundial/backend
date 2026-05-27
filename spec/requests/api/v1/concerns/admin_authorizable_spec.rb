require "rails_helper"

module Api
  module V1
    class AdminProbesController < BaseController
      include AdminAuthorizable

      before_action :require_admin!

      def show
        render json: { ok: true }
      end
    end
  end
end

RSpec.describe "AdminAuthorizable", type: :request do
  before(:all) do # rubocop:disable RSpec/BeforeAfterAll
    Rails.application.routes.draw do
      namespace :api do
        namespace :v1 do
          get "admin_probes/show", to: "admin_probes#show"
        end
      end
    end
  end

  after(:all) { Rails.application.reload_routes! } # rubocop:disable RSpec/BeforeAfterAll

  it "returns 403 for a regular user" do
    login_as(FakeUser.new(id: 1, admin: false, banned_at: nil), scope: :user)
    get "/api/v1/admin_probes/show"
    expect(response).to have_http_status(:forbidden)
    expect(response.parsed_body.dig("error", "code")).to eq("forbidden")
  end

  it "allows an admin user" do
    login_as(FakeUser.new(id: 2, admin: true, banned_at: nil), scope: :user)
    get "/api/v1/admin_probes/show"
    expect(response).to have_http_status(:ok)
    expect(response.parsed_body).to eq("ok" => true)
  end

  it "returns 401 for an unauthenticated request (require_user! runs first)" do
    get "/api/v1/admin_probes/show"
    expect(response).to have_http_status(:unauthorized)
  end
end
