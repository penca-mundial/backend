# Penca Mundial — Backend

REST API for the World Cup 2026 prediction platform.

## Stack

- Ruby 3.3 / Rails 8 (API-only)
- PostgreSQL 16
- `solid_queue` + `solid_cache` (no Redis required)
- Devise + OmniAuth (Google)
- football-data.org as match data source
- Resend for transactional email

## Setup

```bash
git clone git@github.com:penca-mundial/backend.git
cd backend
cp .env.example .env  # fill in values
docker compose up
docker compose exec app bin/rails db:create db:migrate db:seed
```

API runs at http://localhost:3000

Mailcatcher UI for dev emails: http://localhost:1080

## Football data

On a fresh deploy, populate the World Cup teams, players and matches from
football-data.org (set `FOOTBALL_DATA_API_KEY` first):

```bash
docker compose exec app bin/rails football_data:bootstrap
```

It prints the number of teams, players and matches synced. The task is
idempotent — re-running updates existing rows instead of duplicating them.
Live and upcoming matches are then kept fresh automatically by `MatchSyncJob`.

## Tests

```bash
docker compose exec app bundle exec rspec
docker compose exec app bundle exec rubocop
```

## Deployment

The backend deploys to Render via the `render.yaml` Blueprint. Pushes to `main`
auto-deploy.

### Connecting the repo to Render (one-time)

1. In the [Render dashboard](https://dashboard.render.com/), choose **New →
   Blueprint** and select this repository. Render reads `render.yaml` and creates
   the `penca-backend` web service (Docker, production stage of the Dockerfile).
2. Provision the database in [Neon](https://neon.tech/) and copy its connection
   string.
3. Set the environment variables marked `sync: false` in the service's
   **Environment** tab:
   - `RAILS_MASTER_KEY` — contents of `config/master.key`
   - `DATABASE_URL` — the Neon connection string
   - `ADMIN_EMAILS`, `GOOGLE_CLIENT_ID`, `GOOGLE_CLIENT_SECRET`,
     `FOOTBALL_DATA_API_KEY`, `RESEND_API_KEY`, `CORS_ORIGINS`, `FRONTEND_URL`
4. Trigger the first deploy. The Docker entrypoint runs `db:prepare` (creating
   the schema, including the Solid Queue/Cache tables) before booting.
5. Once, from the Render **Shell**, seed reference data: `bin/rails db:seed`.

Health check: `GET /api/v1/health`.

## Environment variables

See `.env.example`.

## Google OAuth setup

Sign-in with Google uses OmniAuth (`omniauth-google-oauth2`). To obtain
credentials:

1. Go to the [Google Cloud Console](https://console.cloud.google.com/) and
   create (or select) a project.
2. **OAuth consent screen** → choose **External**, fill in the app name,
   support email, and developer contact. Add the `email` and `profile`
   scopes. While unverified, add your testers under **Test users**.
3. **Credentials** → **Create credentials** → **OAuth client ID** →
   **Web application**.
4. Add the **Authorized redirect URIs**:
   - Development: `http://localhost:3000/api/v1/auth/google_oauth2/callback`
   - Production: `https://<backend-domain>/api/v1/auth/google_oauth2/callback`
5. Copy the generated **Client ID** and **Client secret** into your `.env`:

   ```bash
   GOOGLE_CLIENT_ID=...
   GOOGLE_CLIENT_SECRET=...
   ```

The app boots fine with these left blank; the Google flow simply stays
disabled until they are set.

## Project tracking

[JIRA board](https://86santiago.atlassian.net/jira/software/projects/SCRUM/boards/1)

## License

Private.
