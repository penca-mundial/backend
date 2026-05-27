require "warden/test/helpers"

# Warden test mode for request specs: `login_as(user, scope: :user)` makes the
# given object the current_user without going through real authentication.
RSpec.configure do |config|
  config.include Warden::Test::Helpers, type: :request

  config.before(type: :request) { Warden.test_mode! }
  config.after(type: :request) { Warden.test_reset! }
end
