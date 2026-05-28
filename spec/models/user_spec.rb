# frozen_string_literal: true

require "rails_helper"

RSpec.describe User, type: :model do
  describe "validations" do
    it "is valid with the default factory attributes" do
      expect(build(:user)).to be_valid
    end

    it "requires an email" do
      expect(build(:user, email: nil)).not_to be_valid
    end

    it "requires a username" do
      expect(build(:user, username: nil)).not_to be_valid
    end

    it "accepts a well-formed username" do
      expect(build(:user, username: "valid_user1")).to be_valid
    end

    it "rejects a username shorter than 3 characters" do
      expect(build(:user, username: "ab")).not_to be_valid
    end

    it "rejects a username longer than 20 characters" do
      expect(build(:user, username: "a" * 21)).not_to be_valid
    end

    it "rejects a username with disallowed characters" do
      expect(build(:user, username: "bad-name!")).not_to be_valid
    end

    it "rejects a duplicate username case-insensitively" do
      create(:user, username: "takenname")
      duplicate = build(:user, username: "TakenName")

      expect(duplicate).not_to be_valid
      expect(duplicate.errors[:username]).to be_present
    end

    it "rejects a duplicate email case-insensitively" do
      create(:user, email: "taken@example.com")
      duplicate = build(:user, email: "TAKEN@example.com")

      expect(duplicate).not_to be_valid
      expect(duplicate.errors[:email]).to be_present
    end

    it "requires a password of at least 8 characters" do
      expect(build(:user, password: "Shor7")).not_to be_valid
    end

    it "requires the password to contain at least one digit" do
      user = build(:user, password: "NoDigitsHere")

      expect(user).not_to be_valid
      expect(user.errors[:password]).to be_present
    end

    it "accepts a password containing a digit" do
      expect(build(:user, password: "Sup3rSecret")).to be_valid
    end
  end

  describe "#normalize_username" do
    it "downcases the username before validation" do
      user = create(:user, username: "MixedCase_1")

      expect(user.username).to eq("mixedcase_1")
    end
  end

  describe "#promote_admin_from_env" do
    around do |example|
      original = ENV["ADMIN_EMAILS"]
      ENV["ADMIN_EMAILS"] = "boss@penca.local, owner@penca.local"
      example.run
      ENV["ADMIN_EMAILS"] = original
    end

    it "promotes a user whose email is listed in ADMIN_EMAILS" do
      expect(create(:user, email: "boss@penca.local")).to be_admin
    end

    it "matches the configured email case-insensitively" do
      expect(create(:user, email: "OWNER@penca.local")).to be_admin
    end

    it "does not promote a user whose email is not listed" do
      expect(create(:user, email: "regular@example.com")).not_to be_admin
    end
  end

  describe ".active" do
    it "includes non-banned users and excludes banned ones" do
      active = create(:user)
      banned = create(:user, :banned)

      expect(described_class.active).to include(active)
      expect(described_class.active).not_to include(banned)
    end
  end

  describe "OAuth users" do
    it "can be created without an explicit password" do
      user = build(:user, :oauth)

      expect(user).to be_valid
      expect { user.save! }.not_to raise_error
    end
  end

  describe "#banned?" do
    it "is true when banned_at is set" do
      expect(build(:user, :banned)).to be_banned
    end

    it "is false when banned_at is nil" do
      expect(build(:user)).not_to be_banned
    end
  end

  describe "#active_for_authentication?" do
    it "is true for a confirmed, non-banned, non-system user" do
      expect(create(:user)).to be_active_for_authentication
    end

    it "is false for a banned user" do
      expect(create(:user, :banned)).not_to be_active_for_authentication
    end

    it "is false for the system account" do
      expect(create(:user, :system)).not_to be_active_for_authentication
    end

    it "is false for an unconfirmed user" do
      expect(build(:user, :unconfirmed)).not_to be_active_for_authentication
    end
  end
end
