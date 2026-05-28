# frozen_string_literal: true

module Auth
  # Applies a new password using Devise's reset_password_by_token. Maps the
  # three failure modes (token never matched, token expired, new password
  # rejected by validations such as :pwned_password) to distinct response
  # codes/statuses so the SPA can render the right copy.
  class ResetPassword < Service
    def initialize(reset_password_token:, password:)
      @token    = reset_password_token.to_s
      @password = password
    end

    def call
      user = User.reset_password_by_token(
        reset_password_token:  @token,
        password:              @password,
        password_confirmation: @password
      )

      return success(user) if user.errors.empty?

      code = classify(user)
      ServiceResult.new(
        errors: user.errors.full_messages,
        data:   { code: code, status: status_for(code) }
      )
    end

    private

    def classify(user)
      details = user.errors.details[:reset_password_token]
      return "token_expired" if details.any? { |e| e[:error] == :expired }
      return "token_invalid" if details.any?

      "validation_error"
    end

    def status_for(code)
      code == "validation_error" ? :unprocessable_content : :bad_request
    end
  end
end
