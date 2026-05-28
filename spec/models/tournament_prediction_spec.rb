# frozen_string_literal: true

require "rails_helper"

RSpec.describe TournamentPrediction, type: :model do
  it "has a valid empty factory (partial predictions are allowed)" do
    expect(build(:tournament_prediction)).to be_valid
  end

  it "has a valid complete factory" do
    expect(build(:tournament_prediction, :complete)).to be_valid
  end

  describe "associations" do
    it { is_expected.to belong_to(:user) }
    it { is_expected.to belong_to(:tournament) }
    it { is_expected.to belong_to(:champion).class_name("Team").optional }
    it { is_expected.to belong_to(:runner_up).class_name("Team").optional }
    it { is_expected.to belong_to(:third_place).class_name("Team").optional }
    it { is_expected.to belong_to(:fourth_place).class_name("Team").optional }
    it { is_expected.to belong_to(:top_scorer).class_name("Player").optional }
  end

  describe "uniqueness" do
    it "cannot store two predictions for the same user and tournament" do
      existing = create(:tournament_prediction)
      duplicate = build(:tournament_prediction, user: existing.user, tournament: existing.tournament)

      expect { duplicate.save! }.to raise_error(ActiveRecord::RecordNotUnique)
    end
  end

  describe "podium distinctness" do
    it "rejects duplicate teams among the four podium spots" do
      tournament = create(:tournament)
      team = create(:team, tournament: tournament)
      prediction = build(:tournament_prediction, tournament: tournament, champion: team, runner_up: team)

      expect(prediction).not_to be_valid
      expect(prediction.errors[:base]).to be_present
    end
  end

  describe "tournament membership" do
    it "rejects a podium team from another tournament" do
      tournament = create(:tournament)
      outsider = create(:team)
      prediction = build(:tournament_prediction, tournament: tournament, champion: outsider)

      expect(prediction).not_to be_valid
      expect(prediction.errors[:champion_id]).to be_present
    end

    it "rejects a top scorer whose team is in another tournament" do
      tournament = create(:tournament)
      outsider_player = create(:player)
      prediction = build(:tournament_prediction, tournament: tournament, top_scorer: outsider_player)

      expect(prediction).not_to be_valid
      expect(prediction.errors[:top_scorer_id]).to be_present
    end
  end

  describe "#locked?" do
    it "is locked when locked_at is set" do
      expect(build(:tournament_prediction, locked_at: Time.current)).to be_locked
    end

    it "is locked once the tournament has started" do
      tournament = create(:tournament, starts_at: 1.day.ago)

      expect(build(:tournament_prediction, tournament: tournament)).to be_locked
    end

    it "is not locked before the tournament starts" do
      tournament = create(:tournament, starts_at: 1.day.from_now)

      expect(build(:tournament_prediction, tournament: tournament)).not_to be_locked
    end
  end
end
