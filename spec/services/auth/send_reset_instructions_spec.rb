# frozen_string_literal: true

require "rails_helper"

RSpec.describe Auth::SendResetInstructions do
  describe ".call" do
    it "sends a reset email when the address belongs to a user" do
      user = create(:user, email: "alice@example.com")
      ActionMailer::Base.deliveries.clear

      result = described_class.call(email: user.email)

      expect(result).to be_success
      expect(ActionMailer::Base.deliveries.last.to).to eq([ user.email ])
    end

    it "is a no-op success when no user matches (anti-enumeration)" do
      ActionMailer::Base.deliveries.clear

      result = described_class.call(email: "nobody@example.com")

      expect(result).to be_success
      expect(ActionMailer::Base.deliveries).to be_empty
    end

    it "downcases the email" do
      user = create(:user, email: "case@example.com")
      ActionMailer::Base.deliveries.clear

      described_class.call(email: "CASE@Example.COM")

      expect(ActionMailer::Base.deliveries.last.to).to eq([ user.email ])
    end
  end
end
