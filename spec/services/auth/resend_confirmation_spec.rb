# frozen_string_literal: true

require "rails_helper"

RSpec.describe Auth::ResendConfirmation do
  include ActiveJob::TestHelper

  describe ".call" do
    it "sends a fresh confirmation email when the address belongs to an unconfirmed user" do
      user = create(:user, :unconfirmed, email: "pending@example.com")
      ActionMailer::Base.deliveries.clear

      result = nil
      perform_enqueued_jobs { result = described_class.call(email: user.email) }

      expect(result).to be_success
      expect(ActionMailer::Base.deliveries.last.to).to eq([ user.email ])
    end

    it "is a no-op success when no user matches (anti-enumeration)" do
      ActionMailer::Base.deliveries.clear

      result = described_class.call(email: "nobody@example.com")

      expect(result).to be_success
      expect(ActionMailer::Base.deliveries).to be_empty
    end

    it "downcases the email so a SHOUTY input still matches" do
      user = create(:user, :unconfirmed, email: "case@example.com")
      ActionMailer::Base.deliveries.clear

      perform_enqueued_jobs { described_class.call(email: "CASE@Example.COM") }

      expect(ActionMailer::Base.deliveries.last.to).to eq([ user.email ])
    end
  end
end
