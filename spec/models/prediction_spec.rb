# frozen_string_literal: true

require "rails_helper"

RSpec.describe Prediction, type: :model do
  it "has a valid factory" do
    expect(build(:prediction)).to be_valid
  end

  it "has a valid knockout factory" do
    expect(build(:prediction, :knockout)).to be_valid
  end

  describe "associations" do
    it { is_expected.to belong_to(:user) }
    it { is_expected.to belong_to(:match) }
    it { is_expected.to belong_to(:predicted_advancing_team).class_name("Team").optional }
  end

  describe "uniqueness" do
    it "cannot store two predictions for the same user and match" do
      existing = create(:prediction)
      duplicate = build(:prediction, user: existing.user, match: existing.match)

      expect { duplicate.save! }.to raise_error(ActiveRecord::RecordNotUnique)
    end
  end

  describe "score validations" do
    it "rejects a negative home score" do
      expect(build(:prediction, predicted_home_score: -1)).not_to be_valid
    end

    it "rejects an away score above 20" do
      expect(build(:prediction, predicted_away_score: 21)).not_to be_valid
    end

    it "accepts scores within the 0..20 range" do
      expect(build(:prediction, predicted_home_score: 0, predicted_away_score: 20)).to be_valid
    end
  end

  describe "advancing-team validations" do
    it "requires an advancing team for a knockout match" do
      match = create(:match, :knockout)
      prediction = build(:prediction, match: match, predicted_advancing_team: nil)

      expect(prediction).not_to be_valid
      expect(prediction.errors[:predicted_advancing_team_id]).to be_present
    end

    it "rejects an advancing team that is not playing the match" do
      match = create(:match, :knockout)
      outsider = create(:team, tournament: match.tournament)
      prediction = build(:prediction, match: match, predicted_advancing_team: outsider)

      expect(prediction).not_to be_valid
      expect(prediction.errors[:predicted_advancing_team_id]).to be_present
    end

    it "does not require an advancing team for a group-stage match" do
      prediction = build(:prediction, match: create(:match), predicted_advancing_team: nil)

      expect(prediction).to be_valid
    end
  end

  describe "#locked?" do
    it "is locked when locked_at is set" do
      expect(build(:prediction, locked_at: Time.current)).to be_locked
    end

    it "is locked when the match is no longer scheduled" do
      expect(build(:prediction, match: create(:match, :live))).to be_locked
    end

    it "is locked when kickoff is within a minute" do
      expect(build(:prediction, match: create(:match, kickoff_at: 30.seconds.from_now))).to be_locked
    end

    it "is not locked for a scheduled match kicking off later" do
      expect(build(:prediction, match: create(:match, kickoff_at: 2.days.from_now))).not_to be_locked
    end
  end
end
