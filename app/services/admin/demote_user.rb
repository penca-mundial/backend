# frozen_string_literal: true

module Admin
  # Demotes the user identified by email from admin. Idempotent: re-running on
  # a non-admin user is a no-op success.
  class DemoteUser < Service
    def initialize(email:)
      @email = email
    end

    def call
      user = User.find_by!(email: @email)
      user.update!(admin: false)
      success(user)
    end
  end
end
