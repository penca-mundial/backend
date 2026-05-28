# frozen_string_literal: true

require "rails_helper"

RSpec.describe Player, type: :model do
  it "has a valid factory" do
    expect(build(:player)).to be_valid
  end

  describe "validations" do
    it { is_expected.to validate_presence_of(:name) }
  end

  describe "associations" do
    it { is_expected.to belong_to(:team) }
    it { is_expected.to have_one(:tournament).through(:team) }
  end

  it "reaches its tournament through its team" do
    tournament = create(:tournament)
    team = create(:team, tournament: tournament)
    player = create(:player, team: team)

    expect(player.tournament).to eq(tournament)
  end

  it "is reachable from its team" do
    player = create(:player)

    expect(player.team.players).to include(player)
  end
end
