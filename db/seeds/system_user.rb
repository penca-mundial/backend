# frozen_string_literal: true

# The system user is a service account that owns records (e.g. the general
# pool group) but can NEVER authenticate. Login is blocked at three layers:
# User#active_for_authentication?, the OAuth callback, and a request spec.
module Seeds
  module SystemUser
    EMAIL    = "system@penca.local"
    USERNAME = "system"

    def self.call
      User.find_or_create_by!(email: EMAIL) do |user|
        user.username     = USERNAME
        user.system       = true
        user.confirmed_at = Time.current
        # A long random password (with a digit, per User's validator) keeps the
        # record valid without storing a guessable credential — login is
        # blocked regardless.
        password = "#{SecureRandom.alphanumeric(40)}1"
        user.password              = password
        user.password_confirmation = password
      end
    end
  end
end
