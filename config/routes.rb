Rails.application.routes.draw do
  # Define your application routes per the DSL in https://guides.rubyonrails.org/routing.html

  # Reveal health status on /up that returns 200 if the app boots with no exceptions, otherwise 500.
  # Can be used by load balancers and uptime monitors to verify that the app is live.
  get "up" => "rails/health#show", as: :rails_health_check

  # Register the Devise mapping for User. We mount only the :confirmations
  # routes so the default mailer (which renders user_confirmation_url) has
  # the URL helper it needs; the rest of the auth surface is served by the
  # /api/v1/auth/* controllers below.
  devise_for :users, skip: %i[sessions registrations passwords unlocks omniauth_callbacks]

  # All application endpoints live under /api/v1. Feature routes are added to
  # this namespace in later phases.
  namespace :api do
    namespace :v1 do
      get "health", to: "health#show"

      # Authentication: cookie-based session, Devise-backed.
      namespace :auth do
        post   "signup", to: "registrations#create"
        post   "login",  to: "sessions#create"
        delete "logout", to: "sessions#destroy"
      end
    end
  end
end
