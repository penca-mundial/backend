# frozen_string_literal: true

module Auth
  # Confirms a user via Devise's confirmation token. Distinguishes "expired"
  # (token was valid once, but past `Devise.confirm_within`) from "invalid"
  # (token never matched any user) so the SPA can render different copy.
  class ConfirmEmail < Service
    def initialize(token:)
      @token = token.to_s
    end

    def call
      user = User.confirm_by_token(@token)
      return success(user) if user.errors.empty?

      code = expired?(user) ? "token_expired" : "token_invalid"
      ServiceResult.new(errors: user.errors.full_messages, data: { code: code })
    end

    private

    def expired?(user)
      user.errors.details[:email].any? { |e| e[:error] == :confirmation_period_expired }
    end
  end
end
