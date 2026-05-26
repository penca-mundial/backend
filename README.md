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

## Tests

```bash
docker compose exec app bundle exec rspec
docker compose exec app bundle exec rubocop
```

## Deployment

Pushes to `main` auto-deploy to Render. See `render.yaml`.

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
