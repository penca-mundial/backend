# frozen_string_literal: true

module Api
  module V1
    module Auth
      # POST /api/v1/auth/login — sign in via cookie session.
      # DELETE /api/v1/auth/logout — clear the cookie session.
      class SessionsController < BaseController
        # CSRF doesn't protect login (the attacker would need the credentials
        # themselves) or logout (the worst case is being logged out). Skipping
        # the check here is what lets warden actually persist to the session
        # instead of writing to the null store.
        skip_forgery_protection

        # Login is the way IN; logout from a still-valid session is also expected
        # to succeed without prior authentication.
        skip_before_action :require_user!

        def create
          result = ::Auth::AuthenticateUser.call(**login_params)

          if result.success?
            warden.set_user(result.data, scope: :user, store: true)
            render json: { user: UserBlueprint.render_as_hash(result.data) }
          else
            render_error(
              code:    result.data[:code],
              message: result.errors.first,
              status:  result.data[:status]
            )
          end
        end

        def destroy
          warden.logout(:user)
          head :no_content
        end

        private

        def warden
          request.env["warden"]
        end

        def login_params
          permitted = params.permit(:email, :password)
          { email: permitted[:email], password: permitted[:password] }
        end
      end
    end
  end
end
