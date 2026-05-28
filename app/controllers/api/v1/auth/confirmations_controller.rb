# frozen_string_literal: true

module Api
  module V1
    module Auth
      # GET  /api/v1/auth/confirmation?confirmation_token=… — confirms the
      #   user (called from the email link) and redirects to the SPA with a
      #   `status` query param indicating the outcome.
      # POST /api/v1/auth/confirmation { email } — resends the confirmation
      #   email; returns 202 regardless of whether the email exists so the
      #   response can't be used to enumerate registered addresses.
      class ConfirmationsController < BaseController
        # Public endpoints. CSRF would otherwise null the session/cookie on
        # POST, which doesn't matter here, but matches the auth namespace.
        skip_before_action :require_user!
        skip_forgery_protection

        def show
          result = ::Auth::ConfirmEmail.call(token: params[:confirmation_token])
          status = result.success? ? "success" : status_from(result)

          redirect_to "#{frontend_url}/confirm-email?status=#{status}", allow_other_host: true
        end

        def create
          ::Auth::ResendConfirmation.call(email: params[:email])
          head :accepted
        end

        # Devise mounts a :new route under our confirmations namespace; the
        # API has no HTML form for that, so the action is a 404 stub.
        def new
          head :not_found
        end

        private

        def status_from(result)
          result.data[:code] == "token_expired" ? "expired" : "invalid"
        end

        def frontend_url
          ENV.fetch("FRONTEND_URL", "http://localhost:5173")
        end
      end
    end
  end
end
