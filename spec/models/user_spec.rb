# frozen_string_literal: true

require "rails_helper"

RSpec.describe User, type: :model do
  describe "associations" do
    it { is_expected.to have_many(:memberships).class_name("GroupMembership").dependent(:destroy) }
    it { is_expected.to have_many(:groups).through(:memberships) }
    it { is_expected.to have_many(:owned_groups).class_name("Group").with_foreign_key(:owner_id).dependent(:destroy) }
    it { is_expected.to have_many(:predictions).dependent(:destroy) }
    it { is_expected.to have_many(:tournament_predictions).dependent(:destroy) }
    it { is_expected.to have_many(:ranking_snapshots).dependent(:destroy) }
    it { is_expected.to have_many(:prediction_scores).through(:predictions) }
  end

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

    describe "avatar_url" do
      it "is valid when blank (nil)" do
        expect(build(:user, avatar_url: nil)).to be_valid
      end

      it "accepts a well-formed https URL" do
        expect(build(:user, avatar_url: "https://lh3.googleusercontent.com/a/photo.jpg")).to be_valid
      end

      it "rejects a non-https (http) URL" do
        user = build(:user, avatar_url: "http://cdn.example.com/a.png")

        expect(user).not_to be_valid
        expect(user.errors[:avatar_url]).to be_present
      end

      it "rejects a malformed URL" do
        expect(build(:user, avatar_url: "not a url")).not_to be_valid
      end
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

  describe "general pool enrolment" do
    include ActiveJob::TestHelper

    around do |example|
      ActiveJob::Base.queue_adapter = :test
      example.run
    end

    it "enqueues AddUserToGeneralPoolJob when a user is confirmed for the first time" do
      user = create(:user, :unconfirmed)

      expect do
        user.update!(confirmed_at: Time.current)
      end.to have_enqueued_job(AddUserToGeneralPoolJob).with(user.id)
    end

    it "enqueues AddUserToGeneralPoolJob on create for an already-confirmed user (Google flow)" do
      expect do
        create(:user, :oauth)
      end.to have_enqueued_job(AddUserToGeneralPoolJob)
    end

    it "does not enqueue for an unconfirmed new user" do
      expect do
        create(:user, :unconfirmed)
      end.not_to have_enqueued_job(AddUserToGeneralPoolJob)
    end

    it "does not enqueue for the system account" do
      expect do
        create(:user, :system)
      end.not_to have_enqueued_job(AddUserToGeneralPoolJob)
    end

    it "does not enqueue on an unrelated update" do
      user = create(:user)
      clear_enqueued_jobs

      expect do
        user.update!(timezone: "America/Montevideo")
      end.not_to have_enqueued_job(AddUserToGeneralPoolJob)
    end
  end
end
