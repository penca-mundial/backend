# frozen_string_literal: true

require "rails_helper"

RSpec.describe Auth::ConfirmEmail do
  # Devise stores a hashed digest of the token; the raw value is what arrives
  # in the URL. The `before_create :generate_confirmation_token` callback
  # overwrites whatever digest we'd pass to the factory, so we save the user
  # first and then patch the columns directly.
  def unconfirmed_with_token(confirmation_sent_at: Time.current, email: "alice@example.com")
    user = create(:user, :unconfirmed, email: email)
    raw, digest = Devise.token_generator.generate(User, :confirmation_token)
    user.update_columns(confirmation_token: digest, confirmation_sent_at: confirmation_sent_at)
    [ user, raw ]
  end

  describe ".call" do
    it "confirms the user and returns success for a valid, in-window token" do
      user, raw = unconfirmed_with_token

      result = described_class.call(token: raw)

      expect(result).to be_success
      expect(user.reload.confirmed_at).to be_present
    end

    it "returns token_invalid for a token that matches no user" do
      result = described_class.call(token: "totally-bogus")

      expect(result).to be_failure
      expect(result.data).to eq(code: "token_invalid")
    end

    it "returns token_expired for a token whose confirmation_sent_at is older than the window" do
      _user, raw = unconfirmed_with_token(confirmation_sent_at: 2.days.ago)

      result = described_class.call(token: raw)

      expect(result).to be_failure
      expect(result.data).to eq(code: "token_expired")
    end

    it "returns token_invalid for a blank token" do
      result = described_class.call(token: "")

      expect(result).to be_failure
      expect(result.data).to eq(code: "token_invalid")
    end
  end
end
