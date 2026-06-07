# frozen_string_literal: true

require "rails_helper"

RSpec.describe Tournament, type: :model do
  include ActiveSupport::Testing::TimeHelpers

  it "has a valid factory" do
    expect(build(:tournament)).to be_valid
  end

  describe "validations" do
    it { is_expected.to validate_presence_of(:name) }
    it { is_expected.to validate_presence_of(:starts_at) }
    it { is_expected.to validate_presence_of(:ends_at) }
  end

  describe "external_code uniqueness (one tournament per competition code)" do
    it "rejects a second tournament with the same external_code via validation" do
      create(:tournament, external_code: "WC")
      duplicate = build(:tournament, external_code: "WC")

      expect(duplicate).not_to be_valid
      expect(duplicate.errors[:external_code]).to be_present
    end

    it "allows multiple tournaments with a nil external_code" do
      create(:tournament, external_code: nil)

      expect(build(:tournament, external_code: nil)).to be_valid
    end

    it "enforces uniqueness at the database level via the partial unique index" do
      create(:tournament, external_code: "WC")
      duplicate = build(:tournament, external_code: "WC")

      # Bypass the validation to prove the DB index itself forbids the duplicate.
      expect { duplicate.save!(validate: false) }.to raise_error(ActiveRecord::RecordNotUnique)
    end
  end

  describe "associations" do
    it { is_expected.to belong_to(:champion).class_name("Team").optional }
    it { is_expected.to belong_to(:runner_up).class_name("Team").optional }
    it { is_expected.to belong_to(:third_place).class_name("Team").optional }
    it { is_expected.to belong_to(:fourth_place).class_name("Team").optional }
    it { is_expected.to belong_to(:top_scorer).class_name("Player").optional }
    it { is_expected.to have_many(:teams) }
    it { is_expected.to have_many(:standings) }
    it { is_expected.to have_many(:players).through(:teams) }

    # Match arrives in a later ticket; assert the reflection without loading it.
    it "declares a has_many :matches association" do
      expect(described_class.reflect_on_association(:matches)).to be_present
    end
  end

  it "exposes players through its teams" do
    tournament = create(:tournament)
    team = create(:team, tournament: tournament)
    player = create(:player, team: team)

    expect(tournament.players).to include(player)
  end

  it "can be assigned a champion team" do
    tournament = create(:tournament)
    team = create(:team, tournament: tournament)

    tournament.update!(champion: team)

    expect(tournament.reload.champion).to eq(team)
  end

  describe "#predictions_lock_at" do
    it "is one minute before the first kickoff of the fixture" do
      tournament = create(:tournament)
      create(:match, tournament: tournament, kickoff_at: Time.utc(2026, 6, 11, 19, 0))
      create(:match, tournament: tournament, kickoff_at: Time.utc(2026, 6, 12, 16, 0))

      expect(tournament.predictions_lock_at).to eq(Time.utc(2026, 6, 11, 18, 59))
    end

    it "is nil when the fixture has not been ingested yet" do
      expect(create(:tournament).predictions_lock_at).to be_nil
    end
  end

  describe "#predictions_locked?" do
    it "locks exactly AT the deadline (boundary: lock_at == now)" do
      freeze_time do
        tournament = create(:tournament)
        create(:match, tournament: tournament, kickoff_at: 1.minute.from_now)

        expect(tournament).to be_predictions_locked
      end
    end

    it "is still open one second before the deadline" do
      freeze_time do
        tournament = create(:tournament)
        create(:match, tournament: tournament, kickoff_at: 1.minute.from_now + 1.second)

        expect(tournament).not_to be_predictions_locked
      end
    end

    it "never locks while there are no matches (no deadline to derive)" do
      expect(create(:tournament, starts_at: 1.year.ago)).not_to be_predictions_locked
    end
  end

  describe "#participating_team_ids" do
    it "returns the distinct home/away ids of the fixture, ignoring tagged-only teams" do
      # Unresolved knockout matches never exist as rows (create-on-resolve,
      # ADR 0001), so nil team slots cannot occur; .compact is pure defense.
      tournament = create(:tournament)
      a = create(:team, tournament: tournament)
      b = create(:team, tournament: tournament)
      c = create(:team, tournament: tournament)
      create(:team, tournament: tournament) # tagged to the tournament but plays no match
      create(:match, tournament: tournament, home_team: a, away_team: b)
      create(:match, tournament: tournament, home_team: a, away_team: c) # a repeats: ids stay distinct

      expect(tournament.participating_team_ids).to contain_exactly(a.id, b.id, c.id)
    end
  end

  describe ".active" do
    it "includes tournaments currently within their playing window and excludes others" do
      current = create(:tournament, starts_at: 1.day.ago, ends_at: 1.day.from_now)
      create(:tournament, starts_at: 2.days.from_now, ends_at: 1.month.from_now) # not started
      create(:tournament, starts_at: 1.month.ago, ends_at: 1.day.ago)            # already ended

      expect(described_class.active).to contain_exactly(current)
    end
  end
end
