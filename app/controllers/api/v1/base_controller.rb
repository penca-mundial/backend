module Api
  module V1
    # Base class for every /api/v1 controller. Centralises CSRF handling, error
    # rescue/formatting, and pagination.
    class BaseController < ApplicationController
      include ActionController::RequestForgeryProtection
      include Authenticatable

      # Cookie-based auth needs CSRF protection. :null_session empties the
      # session on a forged request instead of raising. The OmniAuth callback
      # controller (Phase 2) skips this via `skip_forgery_protection`.
      protect_from_forgery with: :null_session

      # Authenticated, non-banned user required by default; public controllers
      # opt out with `skip_before_action :require_user!`.
      before_action :require_user!

      rescue_from ActiveRecord::RecordNotFound, with: :handle_record_not_found
      rescue_from ActiveRecord::RecordInvalid, with: :handle_record_invalid
      rescue_from Penca::ServiceError, with: :handle_service_error

      private

      def handle_record_not_found(_error)
        render_error(
          code: "not_found",
          message: I18n.t("errors.record_not_found", default: "Recurso no encontrado."),
          status: :not_found
        )
      end

      def handle_record_invalid(error)
        render_error(
          code: "validation_error",
          message: I18n.t("errors.validation_failed", default: "Datos inválidos."),
          status: :unprocessable_content,
          details: { errors: error.record.errors.full_messages }
        )
      end

      def handle_service_error(error)
        render_error(code: "service_error", message: error.message, status: :unprocessable_content)
      end

      # Standardised error envelope: { error: { code, message, details } }.
      def render_error(code:, message:, status:, details: {})
        render json: { error: { code:, message:, details: } }, status:
      end

      # Render a paginated collection and expose the total count to the browser
      # via the X-Total-Count header.
      def render_paginated(collection, blueprint, **options)
        page = collection.page(params[:page]).per(params[:per_page] || 25)
        response.set_header("X-Total-Count", page.total_count.to_s)
        # Blueprinter#render already returns a JSON string; send it as-is to avoid
        # double-encoding.
        render body: blueprint.render(page, **options), content_type: "application/json"
      end
    end
  end
end
