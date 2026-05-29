# Global OmniAuth configuration. The Google strategy itself is registered
# through Devise (see config/initializers/devise.rb).
#
# omniauth-rails_csrf_protection requires the request phase to be a POST, which
# protects the OAuth flow against CSRF. We only allow POST accordingly.
OmniAuth.config.logger = Rails.logger
OmniAuth.config.allowed_request_methods = %i[post]

# Disable omniauth-rails_csrf_protection's authenticity_token check ONLY for the
# request phase (POST /users/auth/:provider). It stays POST-only (above), but no
# longer demands a Rails CSRF token.
#
# Why this is necessary
# ---------------------
# Our SPA frontend is a different origin (localhost:5173) from the API
# (localhost:3000). The Rails CSRF cookie is httpOnly + same-origin, so the SPA
# can never read it and therefore can never put a valid authenticity_token into
# the OmniAuth request form. With the token check on, every initiate POST is
# rejected with ActionController::InvalidAuthenticityToken and bounced to
# /users/auth/failure — the flow never reaches Google.
#
# Why this is safe
# ----------------
#   - The request phase only builds a redirect URL to Google; it mutates no user
#     state. The actual sign-in happens at the CALLBACK phase, which we do NOT
#     exempt — it is protected by the OAuth `state` parameter that Google echoes
#     back and that OmniAuth verifies against the session.
#   - CSRF for our cookie-session API is provided by SameSite=Lax on the session
#     cookie (config/initializers/session_store.rb) plus the CORS allowlist
#     (config/initializers/cors.rb), not by an authenticity_token. This mirrors
#     the ApiCsrfHandling concern already applied to every Api::V1::* controller.
OmniAuth.config.request_validation_phase = nil
# Devise mounts the OmniAuth routes at /users/auth/:provider, so OmniAuth's
# own path-matching middleware needs to look there too (default is /auth).
OmniAuth.config.path_prefix = "/users/auth"

# Don't raise on the request phase in development when credentials are blank;
# log the failure and let the (Phase 2) callback controller handle it.
OmniAuth.config.on_failure = proc do |env|
  OmniAuth::FailureEndpoint.new(env).redirect_to_failure
end
