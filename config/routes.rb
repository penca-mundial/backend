Rails.application.routes.draw do
  # Define your application routes per the DSL in https://guides.rubyonrails.org/routing.html

  # Reveal health status on /up that returns 200 if the app boots with no exceptions, otherwise 500.
  # Can be used by load balancers and uptime monitors to verify that the app is live.
  get "up" => "rails/health#show", as: :rails_health_check

  # Register the Devise mapping for User. We mount only the :confirmations
  # routes so the default mailer (which renders user_confirmation_url) has
  # the URL helper it needs, and route them to our own controller so the
  # email link lands on the same code path as the /api/v1/auth/confirmation
  # endpoints below.
  devise_for :users,
             skip: %i[sessions registrations unlocks],
             controllers: {
               confirmations:      "api/v1/auth/confirmations",
               passwords:          "api/v1/auth/passwords",
               omniauth_callbacks: "api/v1/auth/omniauth_callbacks"
             }

  # All application endpoints live under /api/v1. Feature routes are added to
  # this namespace in later phases.
  namespace :api do
    namespace :v1 do
      get "health", to: "health#show"

      # Authentication: cookie-based session, Devise-backed.
      namespace :auth do
        post   "signup",       to: "registrations#create"
        post   "login",        to: "sessions#create"
        delete "logout",       to: "sessions#destroy"
        get    "confirmation", to: "confirmations#show"
        post   "confirmation", to: "confirmations#create"
        post   "password",     to: "passwords#create"
        put    "password",     to: "passwords#update"
        get    "me",           to: "me#show"
      end

      # Self-service profile editing. /me lives under the auth-protected
      # default — see BaseController#require_user!.
      patch "users/me",          to: "users#update"
      post  "users/me/username", to: "users#claim_username"

      # Public profile of any user (authenticated viewers). The static /me paths
      # above precede these so they aren't swallowed by the :id segment.
      get "users/:id/profile",     to: "user_profiles#show"
      get "users/:id/predictions", to: "user_profiles#predictions"

      # Match predictions (per-match score + knockout advancing team).
      get    "predictions/me",  to: "predictions#index"
      put    "predictions",     to: "predictions#upsert"
      delete "predictions/:id", to: "predictions#destroy"

      # Tournament-wide prediction (podium + top scorer), one per user.
      get "tournament_predictions/me", to: "tournament_predictions#show"
      put "tournament_predictions",    to: "tournament_predictions#upsert"

      # Groups (all authenticated). Collection/specific routes precede :id so
      # they aren't swallowed by the show route.
      get    "groups/me",   to: "groups#index"
      post   "groups/join", to: "groups#join"
      post   "groups",      to: "groups#create"
      get    "groups/:id",  to: "groups#show"
      patch  "groups/:id",  to: "groups#update"
      delete "groups/:id",  to: "groups#destroy"
      post   "groups/:id/regenerate_code",  to: "groups#regenerate_code"
      get    "groups/:id/members",          to: "groups#members"
      delete "groups/:id/members/:user_id", to: "groups#kick_member"

      # Self-leave: the current user removes their own membership.
      delete "groups/:group_id/membership", to: "group_memberships#destroy"

      # Rankings (leaderboards). Global (every user) and member-only group
      # variants; both accept ?window=total|today|week.
      get "rankings/global",     to: "rankings#global"
      get "rankings/groups/:id", to: "rankings#group"
      # Multi-line points/rank evolution for a penca's stats chart (SCRUM-286).
      get "rankings/groups/:id/evolution", to: "rankings#group_evolution"

      # Public fixture. Specific collection routes precede :id so they aren't
      # swallowed by the show route.
      get "matches/live",          to: "matches#live"
      get "matches/today",         to: "matches#today"
      # Home dashboard helpers: the soonest scheduled match and the current
      # tournament's most recent finished matches (the index has no order/limit,
      # so dedicated reads).
      get "matches/next",            to: "matches#next_match"
      get "matches/recent_finished", to: "matches#recent_finished"
      get "matches",                 to: "matches#index"
      get "matches/:id",             to: "matches#show"

      # Public group standings, scoped by ?tournament_id= (defaults to the first
      # tournament). Grouped by group letter, ordered by position.
      get "standings", to: "standings#index"

      # Canonical "current" tournament (active -> upcoming -> most recent past).
      get "tournaments/current", to: "tournaments#current"

      # Calculated group-stage tables for a tournament (composition from
      # Match#group, stats from finished results). Distinct from the mirrored
      # /standings feed above.
      get "tournaments/:id/standings", to: "tournaments/standings#index"

      # Per-user PROJECTED group tables: the official results blended with the
      # current user's predictions for unplayed matches (ADR 0005). Same shape
      # as the official endpoint above; authenticated, additive.
      get "tournaments/:id/standings/projected", to: "tournaments/projected_standings#index"

      # Knockout bracket, data-driven (SCRUM-316): existing KO matches with their
      # topology (feeds_into / bracket_position) and the viewer's locked pick.
      # Public; my_prediction embedded only for a signed-in viewer.
      get "tournaments/:id/bracket", to: "tournaments/bracket#index"

      # Public teams index, scoped by ?tournament_id= (defaults to current).
      get "teams", to: "teams#index"

      # Public players index, filterable by ?team_id= / ?tournament_id=
      # (defaults to current tournament). Paginated.
      get "players", to: "players#index"

      # Public scoring configuration (rule points + phase multipliers), read
      # from the admin-editable models so the rules page never hardcodes them.
      get "scoring_rules", to: "scoring_rules#index"
    end
  end
end
