# frozen_string_literal: true

module Auth
  # Verifies an email/password pair and reports back which guard, if any, the
  # candidate user trips. Pure: no session writes — the SessionsController is
  # responsible for telling Warden to log the returned user in.
  #
  # Failure results carry both a user-facing message in `errors` and the
  # response shape in `data` (`code:` + HTTP `status:`) so the controller can
  # forward them through `render_error` without reproducing the mapping.
  class AuthenticateUser < Service
    INVALID_CREDENTIALS = {
      code:    "invalid_credentials",
      status:  :unauthorized,
      message: "Email o contraseña inválidos."
    }.freeze
    ACCOUNT_BANNED = {
      code:    "account_banned",
      status:  :forbidden,
      message: "Tu cuenta fue suspendida."
    }.freeze
    EMAIL_NOT_CONFIRMED = {
      code:    "email_not_confirmed",
      status:  :unauthorized,
      message: "Confirmá tu dirección de correo para continuar."
    }.freeze

    def initialize(email:, password:)
      @email    = email.to_s.downcase
      @password = password
    end

    def call
      user = User.find_for_authentication(email: @email)

      return reject(INVALID_CREDENTIALS) unless user && user.valid_password?(@password)
      # Block the system account without revealing it exists.
      return reject(INVALID_CREDENTIALS) if user.system?
      return reject(ACCOUNT_BANNED)     if user.banned?
      return reject(EMAIL_NOT_CONFIRMED) unless user.confirmed?

      success(user)
    end

    private

    def reject(reason)
      ServiceResult.new(
        errors: [ reason[:message] ],
        data:   { code: reason[:code], status: reason[:status] }
      )
    end
  end
end
