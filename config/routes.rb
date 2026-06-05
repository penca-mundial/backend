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

      # Match predictions (per-match score + knockout advancing team).
      get    "predictions/me",  to: "predictions#index"
      put    "predictions",     to: "predictions#upsert"
      delete "predictions/:id", to: "predictions#destroy"

      # Tournament-wide prediction (podium + top scorer), one per user.
      get "tournament_predictions/me", to: "tournament_predictions#show"
      put "tournament_predictions",    to: "tournament_predictions#upsert"

      # Public fixture. Specific collection routes precede :id so they aren't
      # swallowed by the show route.
      get "matches/live",  to: "matches#live"
      get "matches/today", to: "matches#today"
      get "matches",       to: "matches#index"
      get "matches/:id",   to: "matches#show"

      # Public group standings, scoped by ?tournament_id= (defaults to the first
      # tournament). Grouped by group letter, ordered by position.
      get "standings", to: "standings#index"

      # Canonical "current" tournament (active -> upcoming -> most recent past).
      get "tournaments/current", to: "tournaments#current"

      # Calculated group-stage tables for a tournament (composition from
      # Match#group, stats from finished results). Distinct from the mirrored
      # /standings feed above.
      get "tournaments/:id/standings", to: "tournaments/standings#index"

      # Public teams index, scoped by ?tournament_id= (defaults to current).
      get "teams", to: "teams#index"

      # Public players index, filterable by ?team_id= / ?tournament_id=
      # (defaults to current tournament). Paginated.
      get "players", to: "players#index"
    end
  end
end
