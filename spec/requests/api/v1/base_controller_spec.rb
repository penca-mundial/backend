require "rails_helper"

# A throwaway item + blueprint and a probe controller subclassing BaseController,
# used to exercise the error-rescue and pagination behaviour without depending on
# real (later-phase) endpoints.
ProbeItem = Struct.new(:id) unless defined?(ProbeItem)

class ProbeItemBlueprint < Blueprinter::Base
  field :id
end

module Api
  module V1
    class ProbesController < BaseController
      # These probes exercise error handling, not auth.
      skip_before_action :require_user!

      def record_not_found
        raise ActiveRecord::RecordNotFound
      end

      def record_invalid
        record = Class.new do
          include ActiveModel::Model
          attr_accessor :email
          validates :email, presence: true

          def self.name
            "FakeRecord"
          end
        end.new
        record.validate
        raise ActiveRecord::RecordInvalid, record
      end

      def service_error
        raise Penca::ServiceError, "regla de negocio"
      end

      def manual_error
        render_error(code: "custom_error", message: "algo salio mal", status: :bad_request, details: { hint: "revisa" })
      end

      def paginated
        items = (1..30).map { |i| ProbeItem.new(i) }
        render_paginated(Kaminari.paginate_array(items), ProbeItemBlueprint)
      end
    end
  end
end

RSpec.describe "Api::V1::BaseController", type: :request do
  # Draw throwaway routes once for this file (route state, not DB records, and
  # restored in after(:all)).
  before(:all) do # rubocop:disable RSpec/BeforeAfterAll
    Rails.application.routes.draw do
      namespace :api do
        namespace :v1 do
          get "health", to: "health#show"
          get "probes/record_not_found", to: "probes#record_not_found"
          get "probes/record_invalid", to: "probes#record_invalid"
          get "probes/service_error", to: "probes#service_error"
          get "probes/manual_error", to: "probes#manual_error"
          get "probes/paginated", to: "probes#paginated"
        end
      end
    end
  end

  after(:all) { Rails.application.reload_routes! } # rubocop:disable RSpec/BeforeAfterAll

  it "serves the api/v1 health endpoint" do
    get "/api/v1/health"
    expect(response).to have_http_status(:ok)
    expect(response.parsed_body).to eq("status" => "ok")
  end

  describe "rescued exceptions return a standardized JSON envelope" do
    it "rescues RecordNotFound as 404" do
      get "/api/v1/probes/record_not_found"
      expect(response).to have_http_status(:not_found)
      expect(response.parsed_body.dig("error", "code")).to eq("not_found")
    end

    it "rescues RecordInvalid as 422 with the record's errors" do
      get "/api/v1/probes/record_invalid"
      expect(response).to have_http_status(:unprocessable_content)
      expect(response.parsed_body.dig("error", "code")).to eq("validation_error")
      expect(response.parsed_body.dig("error", "details", "errors")).to include("Email no puede estar en blanco")
    end

    it "rescues Penca::ServiceError as 422 with the message" do
      get "/api/v1/probes/service_error"
      expect(response).to have_http_status(:unprocessable_content)
      expect(response.parsed_body.dig("error", "code")).to eq("service_error")
      expect(response.parsed_body.dig("error", "message")).to eq("regla de negocio")
    end
  end

  it "renders a custom error via render_error" do
    get "/api/v1/probes/manual_error"
    expect(response).to have_http_status(:bad_request)
    expect(response.parsed_body["error"]).to include(
      "code" => "custom_error", "message" => "algo salio mal", "details" => { "hint" => "revisa" }
    )
  end

  describe "render_paginated" do
    it "sets X-Total-Count and paginates the collection" do
      get "/api/v1/probes/paginated"
      expect(response).to have_http_status(:ok)
      expect(response.headers["X-Total-Count"]).to eq("30")
      expect(response.parsed_body.size).to eq(25)
    end

    it "honours the page and per_page params" do
      get "/api/v1/probes/paginated", params: { page: 2, per_page: 10 }
      expect(response.headers["X-Total-Count"]).to eq("30")
      expect(response.parsed_body.size).to eq(10)
      expect(response.parsed_body.first["id"]).to eq(11)
    end
  end
end
