# frozen_string_literal: true

require "rails_helper"

RSpec.describe Standing, type: :model do
  it "has a valid factory" do
    expect(build(:standing)).to be_valid
  end

  describe "associations" do
    it { is_expected.to belong_to(:tournament) }
    it { is_expected.to belong_to(:team) }
  end

  describe "validations" do
    subject { build(:standing) }

    it { is_expected.to validate_presence_of(:group) }
    it { is_expected.to validate_presence_of(:position) }

    it "requires position to be a positive integer" do
      expect(build(:standing, position: 0)).not_to be_valid
    end

    it "allows a negative goal_difference" do
      expect(build(:standing, goal_difference: -7)).to be_valid
    end

    it "rejects negative counters" do
      expect(build(:standing, points: -1)).not_to be_valid
    end

    it "enforces one standing per team per tournament" do
      existing = create(:standing)
      dup = build(:standing, tournament: existing.tournament, team: existing.team)

      expect(dup).not_to be_valid
    end

    it "allows the same team to have a standing in a different tournament" do
      team = create(:team)
      create(:standing, tournament: team.tournament, team: team)
      other = create(:tournament)

      expect(build(:standing, tournament: other, team: create(:team, tournament: other))).to be_valid
    end
  end

  describe ".ordered" do
    it "orders by group then position" do
      tournament = create(:tournament)
      b1 = create(:standing, tournament: tournament, group: "B", position: 1)
      a2 = create(:standing, tournament: tournament, group: "A", position: 2)
      a1 = create(:standing, tournament: tournament, group: "A", position: 1)

      expect(tournament.standings.ordered).to eq([ a1, a2, b1 ])
    end
  end
end
