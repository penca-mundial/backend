# frozen_string_literal: true

require "rails_helper"

RSpec.describe Auth::ResetPassword do
  # Devise's reset_password_by_token expects to find the user via the HASHED
  # token, so we generate the pair, save the digest, and feed the raw value to
  # the service.
  def user_with_token(reset_password_sent_at: Time.current, email: "alice@example.com")
    user = create(:user, email: email)
    raw, digest = Devise.token_generator.generate(User, :reset_password_token)
    user.update_columns(reset_password_token: digest,
                        reset_password_sent_at: reset_password_sent_at)
    [ user, raw ]
  end

  describe ".call" do
    it "updates the password and returns success for a valid token" do
      user, raw = user_with_token
      old_digest = user.encrypted_password

      result = described_class.call(reset_password_token: raw, password: "BrandN3wPass")

      expect(result).to be_success
      expect(user.reload.encrypted_password).not_to eq(old_digest)
      expect(user.valid_password?("BrandN3wPass")).to be true
    end

    it "returns token_invalid for a token that matches no user" do
      result = described_class.call(reset_password_token: "bogus", password: "BrandN3wPass")

      expect(result).to be_failure
      expect(result.data).to include(code: "token_invalid", status: :bad_request)
    end

    it "returns token_expired when the token is older than reset_password_within" do
      _user, raw = user_with_token(reset_password_sent_at: 7.hours.ago)

      result = described_class.call(reset_password_token: raw, password: "BrandN3wPass")

      expect(result).to be_failure
      expect(result.data).to include(code: "token_expired", status: :bad_request)
    end

    it "returns validation_error for a password without a digit (model validator)" do
      _user, raw = user_with_token

      result = described_class.call(reset_password_token: raw, password: "WeakPasswordNoDigit")

      expect(result).to be_failure
      expect(result.data).to include(code: "validation_error", status: :unprocessable_content)
      expect(result.errors.join).to match(/[Pp]assword/)
    end
  end
end
