# frozen_string_literal: true

module Api
  module V1
    # PATCH /api/v1/users/me        — edit own profile (timezone, avatar_url, username).
    # POST  /api/v1/users/me/username — set the username right after Google sign in.
    class UsersController < BaseController
      def update
        result = ::Users::UpdateProfile.call(
          user:       current_user,
          attributes: profile_params
        )

        if result.success?
          render json: { user: UserBlueprint.render_as_hash(result.data) }
        else
          render_error(
            code:    "validation_error",
            message: I18n.t("errors.validation_failed", default: "Datos inválidos."),
            status:  :unprocessable_content,
            details: { errors: result.errors }
          )
        end
      end

      def claim_username
        result = ::Users::ClaimUsername.call(
          user:     current_user,
          username: username_params[:username]
        )

        if result.success?
          render json: { user: UserBlueprint.render_as_hash(result.data) }
        else
          render_error(
            code:    result.data[:code],
            message: result.errors.first,
            status:  result.data[:status],
            details: { errors: result.errors }
          )
        end
      end

      private

      # Whitelist editable fields. email / admin / system / banned_at are
      # deliberately absent — never accept them from the user.
      def profile_params
        params.permit(:timezone, :avatar_url, :username).to_h
      end

      def username_params
        params.permit(:username)
      end
    end
  end
end
