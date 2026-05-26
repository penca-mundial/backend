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

## Project tracking

[JIRA board](https://86santiago.atlassian.net/jira/software/projects/SCRUM/boards/1)

## License

Private.
