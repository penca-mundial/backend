# frozen_string_literal: true

require "rails_helper"

RSpec.describe Users::UpdateProfile do
  let(:user) do
    create(:user, username: "alice_99", timezone: "UTC", avatar_url: nil)
  end

  describe ".call" do
    it "updates allowed attributes" do
      result = described_class.call(
        user:       user,
        attributes: { timezone: "America/Montevideo", avatar_url: "https://x.io/a.png" }
      )

      expect(result).to be_success
      expect(result.data).to eq(user)
      expect(user.reload.timezone).to eq("America/Montevideo")
      expect(user.avatar_url).to eq("https://x.io/a.png")
    end

    it "accepts string keys (controller passes the permitted hash)" do
      result = described_class.call(
        user:       user,
        attributes: { "timezone" => "America/Argentina/Buenos_Aires" }
      )

      expect(result).to be_success
      expect(user.reload.timezone).to eq("America/Argentina/Buenos_Aires")
    end

    it "silently drops forbidden fields rather than escalating privileges" do
      result = described_class.call(
        user: user,
        attributes: { email: "hacker@example.com", admin: true, system: true,
                      banned_at: Time.current, timezone: "Europe/Madrid" }
      )

      expect(result).to be_success
      user.reload
      expect(user.email).not_to eq("hacker@example.com")
      expect(user.admin).to be(false)
      expect(user.system).to be(false)
      expect(user.banned_at).to be_nil
      expect(user.timezone).to eq("Europe/Madrid")
    end

    it "fails with field errors when validation fails" do
      result = described_class.call(user: user, attributes: { username: "no" })

      expect(result).to be_failure
      expect(result.errors.join).to match(/Nombre de usuario/)
    end
  end
end
