# frozen_string_literal: true

require "rails_helper"

RSpec.describe Team, type: :model do
  it "has a valid factory" do
    expect(build(:team)).to be_valid
  end

  it "builds a valid 3-character code" do
    expect(build(:team).code3.length).to eq(3)
  end

  describe "validations" do
    it { is_expected.to validate_presence_of(:name) }
    it { is_expected.to validate_presence_of(:code3) }
    it { is_expected.to validate_length_of(:code3).is_equal_to(3) }
    it { is_expected.to validate_presence_of(:external_id) }

    it "rejects a duplicate external_id" do
      existing = create(:team)
      duplicate = build(:team, external_id: existing.external_id)

      expect(duplicate).not_to be_valid
      expect(duplicate.errors[:external_id]).to be_present
    end

    it "enforces unique code3 within a tournament at the database level" do
      existing = create(:team)
      duplicate = build(:team, tournament: existing.tournament, code3: existing.code3)

      expect { duplicate.save!(validate: false) }.to raise_error(ActiveRecord::RecordNotUnique)
    end
  end

  describe "associations" do
    it { is_expected.to belong_to(:tournament) }
    it { is_expected.to have_many(:players) }

    it "declares home_matches and away_matches associations" do
      home = described_class.reflect_on_association(:home_matches)
      away = described_class.reflect_on_association(:away_matches)

      expect(home.options[:class_name]).to eq("Match")
      expect(home.foreign_key).to eq("home_team_id")
      expect(away.foreign_key).to eq("away_team_id")
    end
  end

  it "is reachable from its tournament" do
    team = create(:team)

    expect(team.tournament.teams).to include(team)
  end
end
