module Api
  module V1
    # Lightweight API health check (GET /api/v1/health) the frontend can ping.
    class HealthController < BaseController
      def show
        render json: { status: "ok" }
      end
    end
  end
end
