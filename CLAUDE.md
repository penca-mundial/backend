# Penca Mundial — Backend

Rails 8 API-only para una plataforma de predicciones del Mundial 2026.

## Stack

- Ruby 3.3.x, Rails 8 (API-only)
- PostgreSQL 16 (production: Neon)
- solid_queue + solid_cache (sin Redis)
- Devise + omniauth-google-oauth2 + devise-pwned_password
- rack-attack, blueprinter, paper_trail
- RSpec + FactoryBot + WebMock + DatabaseCleaner
- rubocop-rails-omakase

## Convenciones de código

- Todo el código y los comentarios en **inglés**.
- Strings que ve el usuario final en **español** (i18n con `es.yml` como default locale).
- Service Objects para toda la lógica de negocio. La clase base es `app/services/service.rb`; siempre usás `Service.call(...)` desde controllers/jobs.
- Errores de negocio: `raise Penca::ServiceError, "mensaje"`. La base `Service` los convierte en `ServiceResult` con errores.
- Controllers no contienen lógica de negocio — sólo llaman servicios y serializan con Blueprinter.
- Request specs, no controller specs.
- Sin SQLite, en ningún ambiente.
- `WebMock.disable_net_connect!(allow_localhost: true)` en specs; ninguna llamada externa real en tests.

## Estructura

```
app/
  concerns/          # Mixins (ej. ServiceLogger, SoftDeletable)
  controllers/api/v1/...
  decorators/
  exceptions/penca/  # Custom exceptions
  factories/
  jobs/
  models/
  queries/           # Query objects (LeaderboardQuery, etc.)
  serializers/       # Blueprinter blueprints
  services/          # Service objects
  services/concerns/
  validators/
  uploaders/
  lib/penca/
```

Controllers van bajo `app/controllers/api/v1/`. Todo endpoint público vive en `Api::V1::BaseController` o subclase.

## Comandos

```bash
docker compose up                           # Levanta Postgres + mailcatcher + Rails
bin/rails db:create db:migrate db:seed      # Setup DB
bin/rails s                                 # Server
bin/rspec                                   # Tests
bin/lint                                    # rubocop + brakeman + bundle-audit
```

---

# JIRA workflow

El proyecto está en `https://86santiago.atlassian.net`, proyecto **SCRUM**. Todo el backlog está cargado como tickets. Tu trabajo es ir tomando tickets en orden, implementándolos, y cerrándolos. No hay PM ni reviewer — vos sos el único responsable de mover el ticket por el flujo.

## Convenciones de ticket

- Cada ticket tiene un **`External Issue ID`** (campo custom) con formato `task-NNN`. Ese ID es la referencia primaria; el `issue key` de JIRA (ej. `SCRUM-91`) es secundario.
- Las tareas están agrupadas bajo 11 **epics** (`epic-phase-0` a `epic-phase-10`).
- Cada descripción tiene secciones: `Context`, `Scope`, `Out of scope`, `Implementation notes`, `Files`, `Acceptance criteria`, `Dependencies`.
- Las `Dependencies` referencian otros `task-NNN`. **Respetalas**: no arranques una tarea si sus deps están abiertas.

## Workflow para cada ticket

1. **Encontrar la próxima tarea**: la de menor `External Issue ID` que esté en estado `To Do` y cuyas Dependencies estén todas en `Done`.
2. **Mover el ticket a `In Progress`** con `transitionJiraIssue`.
3. **Crear branch**: `feature/task-NNN-slug-corto` desde `main` actualizado.
4. **Implementar todo el Scope del ticket**:
   - Crear/modificar todos los archivos listados en `Files`.
   - Cumplir cada `Acceptance criteria`.
   - Si encontrás una decisión no cubierta por el ticket, optá por lo más simple y consistente con el resto del proyecto (no pidas confirmación por cosas chicas).
5. **Tests**: agregar specs según pide el ticket. Correr `bin/rspec` completo, todo verde.
6. **Lint**: correr `bin/lint`, todo verde.
7. **Commit** siguiendo Conventional Commits:
   - Mensaje formato: `<type>(<scope>): <description>\n\nRefs SCRUM-NNN`
   - Type según corresponda: `feat`, `fix`, `refactor`, `test`, `docs`, `chore`, `style`.
   - Ejemplo: `feat(auth): add RegistrationsController\n\nImplements signup endpoint with confirmation email.\n\nRefs SCRUM-104`
8. **Push** con `git push -u origin feature/task-NNN-slug-corto`.
9. **Comentar en el ticket** con `addCommentToJiraIssue`: link al commit (`https://github.com/penca-mundial/backend/commit/<sha>`) y una línea resumen.
10. **Mover el ticket a `Done`** con `transitionJiraIssue`.
11. **Mergear la rama**: hacer `gh pr create` + `gh pr merge --squash --auto` (o merge directo si no hay branch protection). Volver a `main`, hacer `git pull`, borrar la rama local.
12. **Pasar a la siguiente tarea** automáticamente.

## Reglas importantes

- **NO pidas permiso para empezar** una tarea — si los `Acceptance criteria` están claros, arrancá.
- **SÍ pedí permiso** si:
  - Una dep listada no está cumplida (avisá y pasá a otra tarea sin deps abiertas).
  - El ticket entra en conflicto con código existente de forma no trivial.
  - Una decisión importante de arquitectura no fue cubierta por el ticket ni por este `CLAUDE.md`.
- **Si los tests fallan**: NO commitees. Resolvé hasta que pasen.
- **Si rubocop falla**: corré `bundle exec rubocop -A` (autocorrect), revisá las correcciones, y commiteá.

## Stack-specific gotchas

- **Service.call**: la base de `app/services/service.rb` espera que `.call` retorne un `ServiceResult`. Si tu `call` retorna otra cosa, es bug.
- **Devise modules**: usar siempre `:database_authenticatable, :registerable, :recoverable, :rememberable, :validatable, :confirmable, :omniauthable, omniauth_providers: [:google_oauth2]`. Más `has_pwned_password`.
- **Cookies**: httpOnly, SameSite=Lax, expire_after 30.days. Configurar en `session_store.rb`.
- **CORS**: leer origins de `ENV['CORS_ORIGINS']` (comma-separated). `credentials: true`.
- **External API rate limit**: football-data.org permite 10 req/min en free tier. El client (Phase 3) usa un counter en Rails.cache.
- **Timezone**: el server SIEMPRE en UTC. Conversión a timezone de usuario es en frontend.

## Archivos clave

- `app/services/service.rb` — base de todos los Services. NO modificar sin necesidad.
- `app/controllers/api/v1/base_controller.rb` — base de todos los Controllers.
- `config/routes.rb` — namespace `api/v1` ya estructurado.
- `db/seeds.rb` — corre los seeds en orden: system_user → tournament → teams → scoring_rules → phase_multipliers → general_pool.

## Architectural conventions (must read)

This section is non-negotiable for every backend ticket. Every PR that violates these gets bounced.

### Thin controllers

A controller does ONLY these things:

1. Read params (with strong parameters).
2. Authenticate / authorize via concerns (`require_user!`, `require_admin!`).
3. Call exactly ONE service with those params and `current_user`.
4. Serialize the result with a Blueprint and return JSON.
5. Handle pagination headers when the response is a collection.

A controller MUST NOT contain:

- Conditionals beyond `result.success?`/`result.failure?`.
- ActiveRecord queries (use a Query object or service).
- Business validation (it lives in the service or the model).
- Iterations over collections (the service returns the prepared payload).
- More than ~15 lines per action.

If an action grows beyond that, you missed an abstraction. Move it to a service.

### Thin jobs

Same principle. A job does ONLY:

1. Read its arguments.
2. Call exactly ONE service.
3. Optionally log the result.

Retries, queues, concurrency are configured at class level (`queue_as`, `retry_on`). Business logic does not live in jobs.

### Services

Each service is a single-purpose class under `app/services/<domain>/<verb_noun>.rb`. Inherit from `Service` base class. Pass dependencies explicitly via initializer keyword args. Return a `ServiceResult`.

- One verb per service: `Predictions::UpsertPrediction`, not `Predictions::UpsertOrDeletePrediction`.
- Compose services by calling one from another via `invoke { OtherService.call(...) }` so failures bubble.
- A service that grows past ~80 lines or has more than one private method per public step probably needs to be split.
- No service touches HTTP, params, or response objects.

### Models

Models hold:

- Schema-level concerns (validations of presence/format/range, associations, scopes).
- Tiny, pure read helpers (`#locked?`, `#exact_match?`).

Models do NOT hold:

- Multi-record business processes (e.g. "compute scores for all predictions of a match"). That is a service.
- External I/O (HTTP calls, mail sending). That is a service.
- Conditional persistence beyond `before_save` callbacks for normalization. Anything that decides "should I save?" goes to a service.

### Query objects

Anything more complex than a 2-clause `where` lives under `app/queries/<noun>_query.rb`, inheriting from `ApplicationQuery`. Controllers and services call queries; they never write raw SQL or chains of scopes inline.

### SOLID applied

- **S** (Single responsibility): a class has ONE reason to change. Service named with one verb. Model = schema + invariants. Concern = one orthogonal capability.
- **O** (Open/closed): extend via composition, not by adding flags to existing methods. New behavior → new service.
- **L** (Liskov): subclasses must honor the parent's contract. If a child of `Service` raises something the parent doesn't, refactor.
- **I** (Interface segregation): controllers depend on a narrow service surface, not on the whole model.
- **D** (Dependency inversion): services depend on abstractions (e.g. `mailer`, `client`) injected at initialization, not on global constants. This makes them trivially mockable in specs.

### GRASP applied

- **Information Expert**: put behavior on the class that has the data. `Match#locked?` lives on `Match` because it knows `kickoff_at` and `status`.
- **Creator**: who creates an object? The one that contains it or uses it most closely. `Group` creates the initial `GroupMembership` for its owner.
- **Low Coupling, High Cohesion**: prefer many small services with one job over a "manager" with many responsibilities.
- **Pure Fabrication**: when no domain class is the right home (e.g. "rule evaluator"), it's OK to create a domain-neutral service. `Scoring::MatchRuleEvaluator` is a pure fabrication.
- **Controller** (GRASP role): controllers are intake clerks, not decision makers. Same rule as "thin controllers" above.

### Rails-specific conventions

Follow the official Rails guides:

- RESTful routing. No verb-shaped routes (`/users/ban`) — use a sub-resource (`PATCH /users/:id` with `{banned: true}`) or a member action with a noun (`POST /users/:id/bans`).
- Strong parameters on every write action.
- Prefer `update!`/`save!` (bang methods) inside services so failures raise and are caught by the `Service` base class. Reserve `update`/`save` for cases where you genuinely want to branch on result.
- N+1 prevention: every controller index action must use `includes` or `preload` for the associations the serializer touches. Add specs that count queries with `ActiveRecord::QueryRecorder` for hot endpoints.
- Migrations are reversible: write `change` blocks, not separate `up`/`down`, unless the change is genuinely irreversible.
- Indexes: every foreign key needs an index. Every column queried with `where(...)` in hot paths gets one too.
- Time: always use `Time.current` (timezone-aware), never `Time.now`. Always `Time.zone.parse(...)`, never `Time.parse(...)`.
- Never log secrets: ensure `config.filter_parameters` includes `:password`, `:password_confirmation`, `:current_password`, `:reset_password_token`, `:confirmation_token`, `:secret`, `:authorization`.

### Specs

- Request specs for controllers, NOT controller specs.
- Service specs cover happy path, every business-rule failure branch, every exception rescued by the base class.
- Use FactoryBot factories with traits, not hand-built records.
- Mock external I/O with WebMock. Real HTTP in tests is a bug.
- Coverage minimum 80% (set in SimpleCov). The CI step that runs RSpec also enforces this.

### Authentication & system user

The user with `system: true` and `email: 'system@penca.local'` is a SERVICE ACCOUNT — it exists only to satisfy `owner_id NOT NULL` foreign keys. It must NEVER be able to log in.

Enforcement (all three layers):

1. In `User#active_for_authentication?` (Devise hook), return `false` if `system?`.
2. In `Auth::GoogleOauthCallback`, reject if the resolved user is `system?`.
3. In a request spec, assert that POST /api/v1/auth/login with the system account's email returns 401 even if a valid password somehow existed.

### Process: JIRA assignee

Every ticket the agent picks up MUST be assigned to the project owner (the user invoking `/next`). Assignment happens at the same transition as moving to "In Progress". Use the JIRA account ID of the current user, retrieved via `atlassianUserInfo` once per session and cached.

If the assignee cannot be set (e.g. account lookup fails), surface a warning but proceed — the ticket movement matters more than the assignee.

## PR description hygiene (reiteración explícita)

When running `gh pr create`, the body of the PR MUST NOT contain any of:

- `🤖 Generated with [Claude Code](...)` (or any variant)
- `Generated with Claude Code` (in any form)
- `Co-Authored-By: Claude` (or similar)
- Any reference to Anthropic, Claude, or the tool that produced the code.

If `gh pr create --fill` would otherwise auto-include such text (e.g. from the commit body), use `gh pr create --title "<title>" --body "<body>"` explicitly with hand-crafted body content that contains only:

1. A 1-2 sentence summary of what was implemented.
2. A bulleted list of key changes.
3. The JIRA reference: `Refs SCRUM-NNN`.

Nothing else. No tool attribution. No emoji branding. No "Made with ❤️ by ...".
