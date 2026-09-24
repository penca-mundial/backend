# Magic Penca — Backend API

[![CI](https://github.com/penca-mundial/backend/actions/workflows/ci.yml/badge.svg)](https://github.com/penca-mundial/backend/actions/workflows/ci.yml)

> REST API powering **Magic Penca**, a World Cup 2026 prediction game ("penca") where friends
> predicted match results, competed in private groups, and climbed live leaderboards.

**Status:** 🏆 Ran live during the 2026 FIFA World Cup — now decommissioned and open-sourced as a portfolio piece.
The hosted services (API, database, email) have been shut down; this repository is preserved to show the code and architecture.

This is the **backend**. The companion single-page app lives in
[`penca-mundial/frontend`](https://github.com/penca-mundial/frontend).

---

## What it does

Magic Penca is a football prediction platform. Users sign in, predict scores for every World Cup
match (and a full bracket), and earn points as real results come in. Points feed global and
per-group leaderboards that update automatically as matches finish.

The backend is an **API-only Rails application** that owns all the domain logic:

- **Authentication** — email/password (Devise, with pwned-password checks) and **Google Sign-In** (OmniAuth), issued as cookie-based sessions consumed by the SPA.
- **Predictions & scoring** — per-match score predictions and a tournament bracket, scored by a rules engine with phase multipliers (a knockout hit is worth more than a group-stage one).
- **Groups & leaderboards** — private groups joined by invite code, plus a global pool, each with its own ranking and historical ranking snapshots for standings-over-time charts.
- **Live match data** — matches, teams, players and standings are synced from [football-data.org](https://www.football-data.org/) and kept fresh by background jobs while games are in play.
- **Transactional email** — account confirmation and password reset via Resend.

## Architecture

```
                    Google OAuth
                         │
   React SPA  ──HTTPS──▶ Rails API (this repo) ──▶ PostgreSQL (Neon)
  (Vercel)     JSON      (Render)                       │
                          │  │                          │
                          │  └── Solid Queue (in-Puma)  │  jobs: match sync,
                          │        background jobs ──────┘  scoring, ranking snapshots
                          │
                          └── football-data.org  ·  Resend (email)
```

- **API-only Rails 8.1**, JSON responses serialized with Blueprinter, paginated with Kaminari.
- **Service objects** (`app/services/**`) hold the business logic — auth, scoring, rankings,
  brackets, group memberships — each returning a typed `ServiceResult` and kept out of controllers.
- **Query objects** (`app/queries`) isolate the heavier read paths (leaderboards, profile stats).
- **Solid Queue** runs the background jobs (match sync, locking predictions at kickoff, scoring,
  ranking snapshots) with **no Redis dependency** — it can even run inside Puma on a free tier.
- **CORS** is locked to the SPA origins via the `CORS_ORIGINS` env var; credentials (session
  cookie) are allowed cross-origin.
- Secrets come entirely from environment variables / Rails encrypted credentials — nothing is
  committed to the repo.

## Tech stack

| Area | Choice |
|------|--------|
| Language / framework | Ruby 3.3, Rails 8.1 (API-only) |
| Database | PostgreSQL (hosted on Neon) |
| Background jobs | Solid Queue (DB-backed, no Redis) |
| Auth | Devise + `devise-pwned_password`, OmniAuth Google OAuth2 |
| Serialization | Blueprinter · Pagination: Kaminari |
| External data | football-data.org (via HTTParty client) |
| Email | Resend |
| Testing | RSpec |
| Hosting | Render (API) · Neon (DB) |

## Running it locally

Requires Docker (the Compose file provides Ruby + PostgreSQL).

```bash
git clone https://github.com/penca-mundial/backend.git
cd backend
cp .env.example .env          # fill in values; the app boots without Google/football-data keys
docker compose up
docker compose exec app bin/rails db:create db:migrate db:seed
```

- API: http://localhost:3000
- Dev email inbox (Mailcatcher): http://localhost:1080

Populate World Cup teams, players and matches from football-data.org (set `FOOTBALL_DATA_API_KEY` first):

```bash
docker compose exec app bin/rails football_data:bootstrap
```

The task is idempotent — re-running updates existing rows instead of duplicating them. Live and
upcoming matches are then kept fresh automatically by `MatchSyncJob`.

Run the test suite:

```bash
docker compose exec app bundle exec rspec
```

## Configuration

All configuration is via environment variables — see [`.env.example`](.env.example) for the full
list (database, Rails secrets, Google OAuth, football-data.org, Resend, CORS origins, frontend URL).
The production boot fails fast if any critical variable is missing.

## License

Personal portfolio project. Not affiliated with FIFA or football-data.org.
