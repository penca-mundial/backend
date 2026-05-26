# Cookie-based sessions for Devise/Warden. The cookie is httpOnly and
# SameSite=Lax, secure in production, and lives for 30 days.
Rails.application.config.session_store :cookie_store,
  key: "_penca_session",
  httponly: true,
  same_site: :lax,
  secure: Rails.env.production?,
  expire_after: 30.days

# api_only apps don't insert the session middleware, so add it explicitly using
# the options configured above. (ActionDispatch::Cookies is added in
# config/application.rb, since the session store depends on it.)
Rails.application.config.middleware.use ActionDispatch::Session::CookieStore,
  Rails.application.config.session_options
