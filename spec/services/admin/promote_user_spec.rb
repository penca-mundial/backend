# frozen_string_literal: true

require "rails_helper"

RSpec.describe Admin::PromoteUser do
  describe ".call" do
    it "sets admin=true on the matching user" do
      user = create(:user)

      result = described_class.call(email: user.email)

      expect(result).to be_success
      expect(user.reload.admin).to be true
    end

    it "is a no-op success when the user is already admin" do
      user = create(:user, :admin)

      result = described_class.call(email: user.email)

      expect(result).to be_success
      expect(user.reload.admin).to be true
    end

    it "fails when no user matches the email" do
      result = described_class.call(email: "ghost@example.com")

      expect(result).to be_failure
      expect(result.errors).not_to be_empty
    end
  end
end
