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

  describe "tournament participation" do
    it "rejects a podium team from another tournament" do
      tournament = create(:tournament)
      outsider = create(:team)
      prediction = build(:tournament_prediction, tournament: tournament, champion: outsider)

      expect(prediction).not_to be_valid
      expect(prediction.errors[:champion_id]).to be_present
    end

    it "rejects a podium team tagged to the tournament that plays no matches (seed leftover)" do
      tournament = create(:tournament)
      create(:match, tournament: tournament) # the fixture exists...
      leftover = create(:team, tournament: tournament) # ...but this team is not in it

      prediction = build(:tournament_prediction, tournament: tournament, champion: leftover)

      expect(prediction).not_to be_valid
      expect(prediction.errors[:champion_id]).to be_present
    end

    it "accepts a podium team that actually plays in the fixture" do
      tournament = create(:tournament)
      match = create(:match, tournament: tournament)

      prediction = build(:tournament_prediction, tournament: tournament, champion: match.home_team)

      expect(prediction).to be_valid
    end

    it "rejects a top scorer whose team is in another tournament" do
      tournament = create(:tournament)
      outsider_player = create(:player)
      prediction = build(:tournament_prediction, tournament: tournament, top_scorer: outsider_player)

      expect(prediction).not_to be_valid
      expect(prediction.errors[:top_scorer_id]).to be_present
    end

    it "rejects a top scorer whose team plays no matches; accepts one whose team does" do
      tournament = create(:tournament)
      match = create(:match, tournament: tournament)
      leftover = create(:team, tournament: tournament)

      rejected = build(:tournament_prediction, tournament: tournament,
                                               top_scorer: create(:player, team: leftover))
      accepted = build(:tournament_prediction, tournament: tournament,
                                               top_scorer: create(:player, team: match.home_team))

      expect(rejected).not_to be_valid
      expect(rejected.errors[:top_scorer_id]).to be_present
      expect(accepted).to be_valid
    end
  end

  describe "#locked?" do
    it "is locked when locked_at is set" do
      expect(build(:tournament_prediction, locked_at: Time.current)).to be_locked
    end

    it "is NOT locked after starts_at while the first kickoff is still ahead" do
      # The real-world bug: starts_at (midnight) passed but the opener is hours away.
      tournament = create(:tournament, starts_at: 1.hour.ago)
      create(:match, tournament: tournament, kickoff_at: 6.hours.from_now)

      expect(build(:tournament_prediction, tournament: tournament)).not_to be_locked
    end

    it "is locked once the deadline (first kickoff - 1 minute) has passed" do
      tournament = create(:tournament, starts_at: 1.day.from_now) # starts_at says open...
      create(:match, tournament: tournament, kickoff_at: 30.seconds.from_now) # ...the fixture says locked

      expect(build(:tournament_prediction, tournament: tournament)).to be_locked
    end

    it "is not locked while the fixture is empty" do
      tournament = create(:tournament, starts_at: 1.day.ago)

      expect(build(:tournament_prediction, tournament: tournament)).not_to be_locked
    end
  end
end
