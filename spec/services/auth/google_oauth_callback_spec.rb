# frozen_string_literal: true

require "rails_helper"

RSpec.describe Auth::GoogleOauthCallback do
  def auth_hash(uid: "google-uid-1", email: "alice@example.com", image: "https://img/alice.png")
    {
      provider: "google_oauth2",
      uid:      uid,
      info:     { email: email, name: "Alice", image: image }
    }
  end

  describe ".call" do
    it "creates a fresh OAuth user with no username, confirmed_at set, and the Google avatar" do
      result = nil
      expect do
        result = described_class.call(auth_hash: auth_hash)
      end.to change(User, :count).by(1)

      expect(result).to be_success
      user = result.data
      expect(user.provider).to eq("google_oauth2")
      expect(user.uid).to eq("google-uid-1")
      expect(user.email).to eq("alice@example.com")
      expect(user.avatar_url).to eq("https://img/alice.png")
      expect(user.username).to be_nil
      expect(user.confirmed_at).to be_present
    end

    it "re-uses the existing OAuth user on a subsequent callback" do
      first  = described_class.call(auth_hash: auth_hash).data
      second = nil

      expect do
        second = described_class.call(auth_hash: auth_hash)
      end.not_to change(User, :count)

      expect(second.data).to eq(first)
    end

    it "rejects with use_password when the email already belongs to a password user" do
      create(:user, email: "alice@example.com", provider: nil)

      result = described_class.call(auth_hash: auth_hash)

      expect(result).to be_failure
      expect(result.data).to include(code: "use_password", status: :conflict)
    end

    it "rejects the system account no matter what the hash carries" do
      system_user = create(:user, :system, provider: "google_oauth2", uid: "sys-uid")

      result = described_class.call(auth_hash: auth_hash(uid: system_user.uid, email: system_user.email))

      expect(result).to be_failure
      expect(result.data).to include(code: "system_account", status: :forbidden)
    end

    it "rejects with oauth_failure when the hash is missing uid or email" do
      result = described_class.call(auth_hash: { provider: "google_oauth2", uid: "x", info: {} })

      expect(result).to be_failure
      expect(result.data).to include(code: "oauth_failure", status: :bad_request)
    end
  end
end
