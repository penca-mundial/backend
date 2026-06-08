# frozen_string_literal: true

require "rails_helper"

RSpec.describe Auth::RegisterUser do
  let(:params) do
    { email: "alice@example.com", password: "Sup3rSecret9", username: "alice_99" }
  end

  describe ".call" do
    it "creates an unconfirmed user on success" do
      result = described_class.call(**params)

      expect(result).to be_success
      expect(result.data).to be_a(User)
      expect(result.data.confirmed_at).to be_nil
      expect(result.data.email).to eq("alice@example.com")
      expect(result.data.username).to eq("alice_99")
    end

    it "downcases the username via the User callback" do
      result = described_class.call(**params.merge(username: "ALICE_99"))

      expect(result.data.username).to eq("alice_99")
    end

    it "fails when the email is already taken" do
      create(:user, email: "alice@example.com")

      result = described_class.call(**params)

      expect(result).to be_failure
      expect(result.errors.join).to match(/[Ee]mail/)
    end

    it "fails when the username is malformed" do
      result = described_class.call(**params.merge(username: "Bad Name"))

      expect(result).to be_failure
      expect(result.errors.join).to match(/Nombre de usuario/)
    end

    it "fails when the password has no digit" do
      result = described_class.call(**params.merge(password: "SupersecretNoDigit"))

      expect(result).to be_failure
      expect(result.errors.join).to include("Contraseña")
    end
  end
end
