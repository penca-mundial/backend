# frozen_string_literal: true

require "rails_helper"

RSpec.describe Predictions::UpsertPrediction do
  let(:user)  { create(:user) }
  let(:match) { create(:match, kickoff_at: 1.week.from_now) } # group_stage, scheduled

  def upsert(**overrides)
    args = { user: user, match: match, predicted_home_score: 2, predicted_away_score: 1 }.merge(overrides)
    described_class.call(**args)
  end

  describe "group-stage happy path" do
    it "creates a new prediction" do
      result = nil
      expect { result = upsert }.to change(Prediction, :count).by(1)

      expect(result).to be_success
      expect(result.data).to have_attributes(
        user: user, match: match, predicted_home_score: 2, predicted_away_score: 1
      )
    end

    it "updates the existing prediction instead of creating a second" do
      upsert
      result = nil
      expect { result = upsert(predicted_home_score: 3) }.not_to change(Prediction, :count)

      expect(result.data.reload.predicted_home_score).to eq(3)
    end

    it "is an upsert: calling twice leaves a single row" do
      2.times { upsert }

      expect(Prediction.where(user: user, match: match).count).to eq(1)
    end
  end

  describe "match availability" do
    it "rejects (and persists nothing) when the match is within a minute of kickoff" do
      locked = create(:match, kickoff_at: 30.seconds.from_now)

      result = upsert(match: locked)

      expect(result).to be_failure
      expect(result.errors.join).to include("cerrado")
      expect(Prediction.count).to eq(0)
    end

    it "rejects when the match is not scheduled" do
      live = create(:match, :live, kickoff_at: 1.week.from_now)

      expect(upsert(match: live)).to be_failure
    end
  end

  describe "score range" do
    it "rejects scores above 20" do
      result = upsert(predicted_home_score: 21)

      expect(result).to be_failure
      expect(result.errors.join).to include("goles")
    end

    it "rejects negative scores" do
      expect(upsert(predicted_away_score: -1)).to be_failure
    end
  end

  describe "knockout advancing team" do
    let(:match) { create(:match, :round_of_16, kickoff_at: 1.week.from_now) }

    it "creates the prediction when the advancing team is a participant" do
      result = upsert(predicted_advancing_team_id: match.home_team_id)

      expect(result).to be_success
      expect(result.data.predicted_advancing_team_id).to eq(match.home_team_id)
    end

    it "rejects when no advancing team is given" do
      result = upsert(predicted_advancing_team_id: nil)

      expect(result).to be_failure
      expect(result.errors.join).to include("avanza")
    end

    it "rejects when the advancing team is neither home nor away" do
      other = create(:team, tournament: match.tournament)

      expect(upsert(predicted_advancing_team_id: other.id)).to be_failure
    end
  end
end
