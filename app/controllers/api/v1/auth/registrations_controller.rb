# frozen_string_literal: true

module Api
  module V1
    module Auth
      # POST /api/v1/auth/signup — public signup endpoint.
      class RegistrationsController < BaseController
        # Public endpoint: the very point is to create a user from nothing.
        skip_before_action :require_user!

        def create
          result = ::Auth::RegisterUser.call(**signup_params)

          if result.success?
            render json: { user: UserBlueprint.render_as_hash(result.data) }, status: :created
          else
            render_error(
              code: "validation_error",
              message: I18n.t("errors.validation_failed", default: "Datos inválidos."),
              status: :unprocessable_content,
              details: { errors: result.errors }
            )
          end
        end

        private

        def signup_params
          params.permit(:email, :password, :username).to_h.symbolize_keys
        end
      end
    end
  end
end
