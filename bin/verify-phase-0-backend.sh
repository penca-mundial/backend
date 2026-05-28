#!/usr/bin/env bash
# Penca Mundial — Phase 0 backend verification script
# Run from the backend repo root: ./bin/verify-phase-0.sh
#
# Color-coded output:
#   ✓ green = pass
#   ✗ red   = fail
#   ⚠ yellow = warning (not strictly required by ticket but recommended)
#
# Exits with code 0 if everything critical passes, 1 otherwise.

set -u

# Colors
GREEN=$'\e[32m'
RED=$'\e[31m'
YELLOW=$'\e[33m'
BLUE=$'\e[34m'
BOLD=$'\e[1m'
RESET=$'\e[0m'

PASS=0
FAIL=0
WARN=0

section() {
  echo
  echo "${BOLD}${BLUE}━━━ $1 ━━━${RESET}"
}

check_file() {
  local label="$1" path="$2"
  if [[ -f "$path" ]]; then
    echo "  ${GREEN}✓${RESET} $label  ${path}"
    PASS=$((PASS + 1))
  else
    echo "  ${RED}✗${RESET} $label  ${path}  (missing)"
    FAIL=$((FAIL + 1))
  fi
}

check_dir() {
  local label="$1" path="$2"
  if [[ -d "$path" ]]; then
    echo "  ${GREEN}✓${RESET} $label  ${path}/"
    PASS=$((PASS + 1))
  else
    echo "  ${RED}✗${RESET} $label  ${path}/  (missing)"
    FAIL=$((FAIL + 1))
  fi
}

check_gem() {
  local gem="$1"
  if [[ -f Gemfile.lock ]] && grep -qE "^\s*${gem} " Gemfile.lock; then
    local version
    version=$(grep -E "^\s*${gem} \(" Gemfile.lock | head -1 | sed -E "s/.*\(([^)]+)\).*/\1/")
    echo "  ${GREEN}✓${RESET} ${gem}  (${version})"
    PASS=$((PASS + 1))
  else
    echo "  ${RED}✗${RESET} ${gem}  (not in Gemfile.lock)"
    FAIL=$((FAIL + 1))
  fi
}

check_env_var() {
  local var="$1"
  if [[ -f .env.example ]] && grep -qE "^${var}=" .env.example; then
    echo "  ${GREEN}✓${RESET} ${var} documented in .env.example"
    PASS=$((PASS + 1))
  else
    echo "  ${YELLOW}⚠${RESET}  ${var} not documented in .env.example"
    WARN=$((WARN + 1))
  fi
}

check_content() {
  local label="$1" path="$2" pattern="$3"
  if [[ -f "$path" ]] && grep -qE "$pattern" "$path"; then
    echo "  ${GREEN}✓${RESET} $label"
    PASS=$((PASS + 1))
  else
    echo "  ${RED}✗${RESET} $label  (pattern not found in $path)"
    FAIL=$((FAIL + 1))
  fi
}

check_command() {
  local label="$1"
  shift
  if "$@" > /tmp/penca_verify.log 2>&1; then
    echo "  ${GREEN}✓${RESET} $label"
    PASS=$((PASS + 1))
  else
    echo "  ${RED}✗${RESET} $label  (see /tmp/penca_verify.log)"
    FAIL=$((FAIL + 1))
  fi
}

# ─────────────────────────────────────────────────────────────────────────────
echo "${BOLD}Penca Mundial — Phase 0 backend verification${RESET}"
echo "Running from: $(pwd)"

section "task-001 — Rails 8 API-only initialization"
check_file "Gemfile"                "Gemfile"
check_file ".ruby-version"          ".ruby-version"
check_dir  "app/concerns"           "app/concerns"
check_dir  "app/decorators"         "app/decorators"
check_dir  "app/exceptions/penca"   "app/exceptions/penca"
check_dir  "app/factories"          "app/factories"
check_dir  "app/queries"            "app/queries"
check_dir  "app/serializers"        "app/serializers"
check_dir  "app/services"           "app/services"
check_dir  "app/services/concerns"  "app/services/concerns"
check_dir  "app/validators"         "app/validators"
check_dir  "app/uploaders"          "app/uploaders"
check_dir  "app/lib/penca"          "app/lib/penca"
if [[ -f .ruby-version ]]; then
  ruby_version=$(cat .ruby-version | tr -d '[:space:]')
  if [[ "$ruby_version" =~ ^3\.3\. ]] || [[ "$ruby_version" == "3.3" ]]; then
    echo "  ${GREEN}✓${RESET} .ruby-version is 3.3.x ($ruby_version)"
    PASS=$((PASS + 1))
  else
    echo "  ${YELLOW}⚠${RESET}  .ruby-version is $ruby_version (expected 3.3.x)"
    WARN=$((WARN + 1))
  fi
fi
if [[ -f Gemfile.lock ]]; then
  rails_version=$(grep -E "^\s+rails \(" Gemfile.lock | head -1 | sed -E "s/.*\(([^)]+)\).*/\1/")
  if [[ "$rails_version" =~ ^8\. ]]; then
    echo "  ${GREEN}✓${RESET} Rails 8.x ($rails_version)"
    PASS=$((PASS + 1))
  else
    echo "  ${RED}✗${RESET} Rails version is $rails_version (expected 8.x)"
    FAIL=$((FAIL + 1))
  fi
fi

section "task-002 — Docker + Postgres"
check_file "Dockerfile"                  "Dockerfile"
check_file "docker-compose.yml"          "docker-compose.yml"
check_file "bin/docker-entrypoint"       "bin/docker-entrypoint"
check_file ".env.example"                ".env.example"
check_content "database.yml uses DATABASE_URL" "config/database.yml" "DATABASE_URL|url:.*ENV"

section "task-003 — Lint stack"
check_file ".rubocop.yml"   ".rubocop.yml"
check_file "bin/lint"       "bin/lint"
check_gem  "rubocop"
check_gem  "rubocop-rails-omakase"
check_gem  "brakeman"
check_gem  "bundler-audit"

section "task-004 — RSpec + FactoryBot"
check_file "spec/spec_helper.rb"    "spec/spec_helper.rb"
check_file "spec/rails_helper.rb"   "spec/rails_helper.rb"
check_file ".rspec"                  ".rspec"
check_dir  "spec/factories"          "spec/factories"
check_gem  "rspec-rails"
check_gem  "factory_bot_rails"
check_gem  "faker"
check_gem  "webmock"
check_gem  "database_cleaner-active_record"
check_content "WebMock disabled in specs"     "spec/spec_helper.rb" "WebMock.disable_net_connect" || \
  check_content "WebMock disabled in specs"   "spec/rails_helper.rb" "WebMock.disable_net_connect"

section "task-005 — Service base classes"
check_file "app/services/service.rb"                "app/services/service.rb"
check_file "app/services/service_result.rb"         "app/services/service_result.rb"
check_file "app/concerns/service_logger.rb"         "app/concerns/service_logger.rb"
check_file "app/exceptions/penca/service_error.rb"  "app/exceptions/penca/service_error.rb"
check_file "app/queries/application_query.rb"       "app/queries/application_query.rb"
check_content "Service.call defined"            "app/services/service.rb" "def self\.call"
check_content "ServiceResult class"             "app/services/service_result.rb" "class ServiceResult"

section "task-006 — Devise"
check_gem  "devise"
check_gem  "devise-pwned_password"
check_file "config/initializers/devise.rb"        "config/initializers/devise.rb"
check_file "config/initializers/session_store.rb" "config/initializers/session_store.rb"
check_content "Devise navigational_formats empty" "config/initializers/devise.rb" "navigational_formats"
check_content "Cookie httpOnly httponly"           "config/initializers/session_store.rb" "(httponly|http_only).*true"

section "task-007 — OmniAuth Google"
check_gem  "omniauth"
check_gem  "omniauth-google-oauth2"
check_gem  "omniauth-rails_csrf_protection"
check_env_var "GOOGLE_CLIENT_ID"
check_env_var "GOOGLE_CLIENT_SECRET"

section "task-008 — CORS"
check_gem  "rack-cors"
check_file "config/initializers/cors.rb" "config/initializers/cors.rb"
check_content "CORS reads from ENV"         "config/initializers/cors.rb" "ENV"
check_content "CORS allows credentials"     "config/initializers/cors.rb" "credentials.*true"
check_env_var "CORS_ORIGINS"

section "task-009 — Blueprinter"
check_gem  "blueprinter"
check_gem  "oj"
check_file "config/initializers/blueprinter.rb" "config/initializers/blueprinter.rb"

section "task-010 — Rack::Attack"
check_gem  "rack-attack"
check_file "config/initializers/rack_attack.rb" "config/initializers/rack_attack.rb"
check_content "Rack::Attack mounted as middleware" "config/application.rb" "Rack::Attack" || \
  check_content "Rack::Attack mounted as middleware" "config/initializers/rack_attack.rb" "use Rack::Attack"

section "task-011 — paper_trail"
check_gem  "paper_trail"
versions_migration=$(find db/migrate -name "*create_versions*" 2>/dev/null | head -1)
if [[ -n "$versions_migration" ]]; then
  echo "  ${GREEN}✓${RESET} versions migration  ${versions_migration}"
  PASS=$((PASS + 1))
else
  echo "  ${RED}✗${RESET} versions migration  (no db/migrate/*create_versions* found)"
  FAIL=$((FAIL + 1))
fi

section "task-012 — solid_queue + solid_cache"
check_gem  "solid_queue"
check_gem  "solid_cache"
check_file "config/queue.yml"      "config/queue.yml"
check_file "config/recurring.yml"  "config/recurring.yml"
check_content "ActiveJob uses solid_queue" "config/application.rb" "solid_queue" || \
  check_content "ActiveJob uses solid_queue" "config/environments/production.rb" "solid_queue"

section "task-013 — Api::V1::BaseController"
check_file "app/controllers/api/v1/base_controller.rb" "app/controllers/api/v1/base_controller.rb"
check_content "Routes have api/v1 namespace"  "config/routes.rb" "namespace :v1|api.v1"

section "task-014 — Authenticatable / AdminAuthorizable"
check_file "app/controllers/concerns/authenticatable.rb"      "app/controllers/concerns/authenticatable.rb"
check_file "app/controllers/concerns/admin_authorizable.rb"   "app/controllers/concerns/admin_authorizable.rb"

section "task-015 — i18n"
check_file "config/locales/en.yml"  "config/locales/en.yml"
check_file "config/locales/es.yml"  "config/locales/es.yml"
check_content "default_locale = :es"  "config/application.rb" "default_locale\s*=\s*:es"

section "task-016 — Resend / mailer"
check_gem  "resend"
check_file "app/mailers/application_mailer.rb"  "app/mailers/application_mailer.rb"
check_env_var "RESEND_API_KEY"
check_env_var "MAIL_FROM"

section "task-017 — render.yaml"
check_file "render.yaml" "render.yaml"

# ─────────────────────────────────────────────────────────────────────────────
section "Runtime checks"

if command -v bundle > /dev/null 2>&1; then
  check_command "bundle exec rails about runs"       bundle exec rails about
  check_command "bundle exec rspec runs (any tests)" bundle exec rspec --dry-run
  check_command "bundle exec rubocop runs"           bundle exec rubocop --no-color
  check_command "bundle exec brakeman runs"          bundle exec brakeman --no-pager --quiet
  check_command "bundle-audit check passes"          bundle exec bundle-audit check --update
else
  echo "  ${YELLOW}⚠${RESET}  bundle not in PATH — skipping runtime checks"
  WARN=$((WARN + 1))
fi

# ─────────────────────────────────────────────────────────────────────────────
section "Summary"
TOTAL=$((PASS + FAIL))
echo "  ${GREEN}Passed: $PASS${RESET}"
echo "  ${RED}Failed: $FAIL${RESET}"
echo "  ${YELLOW}Warnings: $WARN${RESET}"
echo

if [[ $FAIL -eq 0 ]]; then
  echo "  ${BOLD}${GREEN}Phase 0 backend looks healthy. ✓${RESET}"
  echo "  Ready to start Phase 1 with /next 1"
  exit 0
else
  echo "  ${BOLD}${RED}Phase 0 backend has $FAIL issue(s). Review above. ✗${RESET}"
  exit 1
fi
