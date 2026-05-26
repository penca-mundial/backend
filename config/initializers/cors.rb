# Be sure to restart your server when you modify this file.

# Cross-Origin Resource Sharing for the SPA frontend (Vercel) talking to this
# API (Render). Allowed origins come from CORS_ORIGINS (comma-separated); in
# development we default to the Vite dev server. Credentials are allowed so the
# session cookie is sent on cross-origin requests.

allowed_origins =
  ENV.fetch("CORS_ORIGINS") { Rails.env.development? ? "http://localhost:5173" : "" }
    .split(",")
    .map(&:strip)
    .reject(&:blank?)

Rails.application.config.middleware.insert_before 0, Rack::Cors do
  allow do
    origins(*allowed_origins)

    resource "*",
      headers: :any,
      methods: %i[get post patch put delete options head],
      credentials: true,
      expose: [ "X-Total-Count" ]
  end
end
