# frozen_string_literal: true

module Auth
  # Triggers Devise's password-reset email for the given address. Always
  # reports success so the endpoint stays anti-enumerative: the response is
  # the same whether or not the email is registered.
  class SendResetInstructions < Service
    def initialize(email:)
      @email = email.to_s.downcase
    end

    def call
      User.send_reset_password_instructions(email: @email)
      success
    end
  end
end
