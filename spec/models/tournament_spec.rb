# frozen_string_literal: true

require "rails_helper"

RSpec.describe Tournament, type: :model do
  it "has a valid factory" do
    expect(build(:tournament)).to be_valid
  end

  describe "validations" do
    it { is_expected.to validate_presence_of(:name) }
    it { is_expected.to validate_presence_of(:starts_at) }
    it { is_expected.to validate_presence_of(:ends_at) }
  end

  describe "associations" do
    it { is_expected.to belong_to(:champion).class_name("Team").optional }
    it { is_expected.to belong_to(:runner_up).class_name("Team").optional }
    it { is_expected.to belong_to(:third_place).class_name("Team").optional }
    it { is_expected.to belong_to(:fourth_place).class_name("Team").optional }
    it { is_expected.to belong_to(:top_scorer).class_name("Player").optional }
    it { is_expected.to have_many(:teams) }
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
end
