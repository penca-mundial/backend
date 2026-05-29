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
    end
  end
end
