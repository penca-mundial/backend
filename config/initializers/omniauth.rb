# Global OmniAuth configuration. The Google strategy itself is registered
# through Devise (see config/initializers/devise.rb).
#
# omniauth-rails_csrf_protection requires the request phase to be a POST, which
# protects the OAuth flow against CSRF. We only allow POST accordingly.
OmniAuth.config.logger = Rails.logger
OmniAuth.config.allowed_request_methods = %i[post]

# Don't raise on the request phase in development when credentials are blank;
# log the failure and let the (Phase 2) callback controller handle it.
OmniAuth.config.on_failure = proc do |env|
  OmniAuth::FailureEndpoint.new(env).redirect_to_failure
end
