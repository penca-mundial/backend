# Fail fast in production when a critical environment variable is missing.
#
# Without this check the app boots and fails silently much later: CORS
# configures zero allowed origins (every browser call dies), the football-data
# client sends an empty X-Auth-Token (sync jobs 4xx against the API), Google
# OAuth bounces every login, and auth redirects fall back to localhost.
#
# Raising here is safe for the Docker build: the image build never boots Rails
# (only `bootsnap precompile`), so this runs at deploy boot (db:prepare /
# server / jobs), exactly when the real Render environment is present.
if Rails.env.production?
  required = %w[
    CORS_ORIGINS
    FOOTBALL_DATA_API_KEY
    GOOGLE_CLIENT_ID
    GOOGLE_CLIENT_SECRET
    FRONTEND_URL
  ]
  missing = required.select { |key| ENV[key].to_s.strip.empty? }

  if missing.any?
    raise "Missing required environment variables: #{missing.join(', ')}. " \
          "Set them in the Render dashboard (see render.yaml envVars)."
  end
end
