# frozen_string_literal: true

module Auth
  # Resends Devise's confirmation email for the given address. Always reports
  # success — controllers responding to this should return the same status code
  # regardless of whether the email exists, to avoid leaking which addresses
  # are registered.
  class ResendConfirmation < Service
    def initialize(email:)
      @email = email.to_s.downcase
    end

    def call
      User.send_confirmation_instructions(email: @email)
      success
    end
  end
end
