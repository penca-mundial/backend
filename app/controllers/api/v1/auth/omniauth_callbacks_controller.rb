# frozen_string_literal: true

module Api
  module V1
    module Auth
      # GET /users/auth/google_oauth2/callback — handles the Google OAuth
      # callback. On success we Warden-set the user and redirect to the SPA's
      # callback page with `needs_username=true|false`; on a known failure
      # we redirect to /login with an error code; the OmniAuth-level failure
      # endpoint (#failure) covers strategy errors.
      class OmniauthCallbacksController < BaseController
        skip_before_action :require_user!
        skip_forgery_protection

        def google_oauth2
          result = ::Auth::GoogleOauthCallback.call(auth_hash: request.env["omniauth.auth"])

          if result.success?
            user = result.data
            warden.set_user(user, scope: :user, store: true)
            redirect_to(
              "#{frontend_url}/auth/google/callback?needs_username=#{user.username.blank?}",
              allow_other_host: true
            )
          else
            redirect_to "#{frontend_url}/login?error=#{result.data[:code]}",
                        allow_other_host: true
          end
        end

        # OmniAuth routes strategy-level failures here.
        def failure
          redirect_to "#{frontend_url}/login?error=oauth_failure", allow_other_host: true
        end

        private

        def warden
          request.env["warden"]
        end

        def frontend_url
          ENV.fetch("FRONTEND_URL", "http://localhost:5173")
        end
      end
    end
  end
end
