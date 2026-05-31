# Cookie-based sessions for Devise/Warden. The cookie is httpOnly and
# SameSite=Lax, secure in production, and lives for 30 days.
Rails.application.config.session_store :cookie_store,
  key: "_penca_session",
  httponly: true,
  same_site: :lax,
  secure: Rails.env.production?,
  expire_after: 30.days

# api_only apps don't insert the session middleware, so add it explicitly using
# the options configured above.
#
# Ordering matters: cookies + session MUST run before Warden::Manager (inserted
# by Devise during engine load) so the session is loaded before anything reads
# Warden. Otherwise a middleware above the session store that touches
# `env["warden"].user` (e.g. the Rack::Attack `predictions` throttle) makes
# Warden fetch from an empty session and memoize a nil user for the rest of the
# request — turning authenticated writes into spurious 401s. `insert_before`
# resolves Warden::Manager because Devise registers it before config
# initializers run; Cookies is inserted before the session store, which depends
# on it.
Rails.application.config.middleware.insert_before Warden::Manager,
  ActionDispatch::Session::CookieStore, Rails.application.config.session_options
Rails.application.config.middleware.insert_before ActionDispatch::Session::CookieStore,
  ActionDispatch::Cookies
