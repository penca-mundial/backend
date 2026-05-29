# Controller concern that opts the whole /api/v1 namespace out of Rails'
# HTML-form CSRF token verification.
#
# Why this exists
# ---------------
# This app is `ActionController::API` only (`config.api_only = true`), so the
# `ActionDispatch::Flash` middleware is NOT in the stack and `request.flash=`
# is undefined. The previous setup used `protect_from_forgery with:
# :null_session`, whose `handle_unverified_request` calls `request.flash = nil`
# — that raises `NoMethodError` on every tokenless POST and turns signup into
# an HTTP 500. The `authenticity_token` mechanism is HTML-form specific and
# incompatible with a JSON + cookies API.
#
# What this does
# --------------
# It registers the forgery-protection machinery with the `:exception` strategy
# (so the `verify_authenticity_token` before_action exists and never touches
# `flash`) and then skips that before_action for the whole namespace. The net
# effect is no token verification, with the skip stated explicitly rather than
# left implicit — if anyone removes the skip, requests fail loudly with a clean
# 4xx instead of the old flash crash.
#
# Why this is safe
# ----------------
# CSRF protection for our cookie-session API is provided by three layers that
# do not depend on a per-request token:
#
#   - SameSite on the session cookie (config/initializers/session_store.rb)
#     stops the browser from attaching the session cookie to cross-site
#     requests.
#   - The CORS allowlist with `credentials: true` (config/initializers/cors.rb)
#     only lets approved origins read authenticated responses.
#   - Origin/preflight enforcement by rack-cors rejects requests from origins
#     that are not on the allowlist.
#
# Including this concern in Api::V1::BaseController applies the policy to every
# current and future Api::V1::* controller, so individual controllers never
# need their own `skip_forgery_protection` call.
module ApiCsrfHandling
  extend ActiveSupport::Concern

  included do
    include ActionController::RequestForgeryProtection

    # :exception (not :null_session) because the API stack has no Flash
    # middleware; the :null_session strategy crashes on `request.flash=`.
    protect_from_forgery with: :exception

    # Opt the whole namespace out of token verification. Cookie + CORS layers
    # (see above) provide the actual CSRF protection.
    skip_before_action :verify_authenticity_token
  end
end
