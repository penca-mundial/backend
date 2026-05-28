# frozen_string_literal: true

require "rails_helper"

RSpec.describe Auth::AuthenticateUser do
  let(:password) { "Sup3rSecret9" }
  let!(:user)    { create(:user, password: password, email: "alice@example.com") }

  describe ".call" do
    it "succeeds with the right email + password" do
      result = described_class.call(email: user.email, password: password)

      expect(result).to be_success
      expect(result.data).to eq(user)
    end

    it "is case-insensitive on email" do
      result = described_class.call(email: "ALICE@example.com", password: password)

      expect(result).to be_success
      expect(result.data).to eq(user)
    end

    it "returns invalid_credentials for a wrong password" do
      result = described_class.call(email: user.email, password: "wrong-password-9")

      expect(result).to be_failure
      expect(result.data).to include(code: "invalid_credentials", status: :unauthorized)
    end

    it "returns invalid_credentials for a non-existent email (same code, no leak)" do
      result = described_class.call(email: "ghost@example.com", password: password)

      expect(result).to be_failure
      expect(result.data).to include(code: "invalid_credentials", status: :unauthorized)
    end

    it "returns invalid_credentials for the system account even with the right password" do
      system_user = create(:user, :system, password: password)

      result = described_class.call(email: system_user.email, password: password)

      expect(result).to be_failure
      expect(result.data).to include(code: "invalid_credentials", status: :unauthorized)
    end

    it "returns account_banned for a banned user with the right password" do
      banned = create(:user, :banned, password: password, email: "ban@example.com")

      result = described_class.call(email: banned.email, password: password)

      expect(result).to be_failure
      expect(result.data).to include(code: "account_banned", status: :forbidden)
    end

    it "returns email_not_confirmed for an unconfirmed user with the right password" do
      pending_user = create(:user, :unconfirmed, password: password, email: "pending@example.com")

      result = described_class.call(email: pending_user.email, password: password)

      expect(result).to be_failure
      expect(result.data).to include(code: "email_not_confirmed", status: :unauthorized)
    end
  end
end
