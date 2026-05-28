# frozen_string_literal: true

module Api
  module V1
    module Auth
      # POST /api/v1/auth/password { email } — request a reset email.
      # PUT  /api/v1/auth/password { reset_password_token, password } — set new password.
      class PasswordsController < BaseController
        skip_before_action :require_user!
        skip_forgery_protection

        # Request a reset link. Always responds 202 so the caller can't tell
        # whether the email exists.
        def create
          ::Auth::SendResetInstructions.call(email: params[:email])
          head :accepted
        end

        # Submit the new password along with the reset token. On success the
        # user is returned (no automatic sign-in — the SPA can then call
        # /auth/login). Failures map to:
        #   token_invalid  → 400
        #   token_expired  → 400
        #   validation_*   → 422
        def update
          result = ::Auth::ResetPassword.call(
            reset_password_token: params[:reset_password_token],
            password:              params[:password]
          )

          if result.success?
            render json: { user: UserBlueprint.render_as_hash(result.data) }
          else
            render_error(
              code:    result.data[:code],
              message: result.errors.first,
              status:  result.data[:status]
            )
          end
        end

        # API has no HTML forms — stub Devise's recoverable :new and :edit so
        # those routes don't blow up with an "action not found" 500.
        def new = head(:not_found)
        def edit = head(:not_found)
      end
    end
  end
end
