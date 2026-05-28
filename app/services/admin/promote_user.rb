# frozen_string_literal: true

module Admin
  # Promotes the user identified by email to admin. Idempotent: re-running on
  # an already-admin user is a no-op success.
  class PromoteUser < Service
    def initialize(email:)
      @email = email
    end

    def call
      user = User.find_by!(email: @email)
      user.update!(admin: true)
      success(user)
    end
  end
end
