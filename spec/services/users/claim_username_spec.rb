# frozen_string_literal: true

require "rails_helper"

RSpec.describe Users::ClaimUsername do
  describe ".call" do
    context "when the user has no username yet" do
      let(:user) { create(:user, :oauth, username: nil) }

      it "sets the username (lowercased) and succeeds" do
        result = described_class.call(user: user, username: "Bob_99")

        expect(result).to be_success
        expect(user.reload.username).to eq("bob_99")
      end

      it "returns a 422-shaped failure when the username is invalid" do
        result = described_class.call(user: user, username: "no")

        expect(result).to be_failure
        expect(result.data).to include(code: "validation_error", status: :unprocessable_content)
        expect(result.errors.join).to match(/[Uu]sername/)
      end

      it "returns a 422-shaped failure when the username is already taken" do
        create(:user, username: "taken_name")

        result = described_class.call(user: user, username: "Taken_Name")

        expect(result).to be_failure
        expect(result.data[:status]).to eq(:unprocessable_content)
        expect(result.errors.join).to match(/[Uu]sername/)
      end
    end

    context "when the user already has a username" do
      let(:user) { create(:user, username: "alice_99") }

      it "refuses to overwrite and returns a 409-shaped failure" do
        result = described_class.call(user: user, username: "new_name")

        expect(result).to be_failure
        expect(result.data).to include(code: "username_already_set", status: :conflict)
        expect(user.reload.username).to eq("alice_99")
      end
    end
  end
end
