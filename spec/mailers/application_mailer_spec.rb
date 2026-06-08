# frozen_string_literal: true

require "rails_helper"

RSpec.describe ApplicationMailer do
  describe ".from_address" do
    around do |example|
      original = ENV.fetch("MAILER_FROM", nil)
      example.run
    ensure
      original.nil? ? ENV.delete("MAILER_FROM") : ENV["MAILER_FROM"] = original
    end

    it "reads the sender from MAILER_FROM" do
      ENV["MAILER_FROM"] = "Penca <no-reply@verified.example>"

      expect(described_class.from_address).to eq("Penca <no-reply@verified.example>")
    end

    it "falls back to a real-domain default, never the unsendable @penca.local" do
      ENV.delete("MAILER_FROM")

      expect(described_class.from_address).to eq(ApplicationMailer::DEFAULT_FROM)
      expect(described_class.from_address).not_to include("penca.local")
    end
  end

  it "stamps Devise confirmation emails with the configured sender" do
    user = create(:user, :unconfirmed)

    mail = Devise::Mailer.confirmation_instructions(user, "token-abc")

    expect(mail.from).to eq([ Mail::Address.new(described_class.from_address).address ])
    expect(mail.from.join).not_to include("penca.local")
  end
end
