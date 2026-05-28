# frozen_string_literal: true

require "rails_helper"

RSpec.describe Match, type: :model do
  it "has a valid factory" do
    expect(build(:match)).to be_valid
  end

  describe "associations" do
    it { is_expected.to belong_to(:tournament) }
    it { is_expected.to belong_to(:home_team).class_name("Team") }
    it { is_expected.to belong_to(:away_team).class_name("Team") }
    it { is_expected.to belong_to(:advancing_team).class_name("Team").optional }
  end

  describe "status enum" do
    it "defines the expected statuses" do
      expect(described_class.statuses.keys)
        .to match_array(%w[scheduled live finished postponed cancelled])
    end

    it "exposes prefixed predicate methods" do
      expect(build(:match, :live)).to be_status_live
      expect(build(:match)).to be_status_scheduled
    end
  end

  describe "phase enum" do
    it "defines the expected phases" do
      expect(described_class.phases.keys).to match_array(
        %w[group_stage round_of_32 round_of_16 quarter_final semi_final third_place final]
      )
    end

    it "exposes prefixed predicate methods" do
      expect(build(:match, :knockout)).to be_phase_round_of_16
    end
  end

  describe "scopes" do
    it "filter matches by status" do
      scheduled = create(:match)
      live = create(:match, :live)
      finished = create(:match, :finished)

      expect(described_class.scheduled).to contain_exactly(scheduled)
      expect(described_class.live).to contain_exactly(live)
      expect(described_class.finished).to contain_exactly(finished)
    end
  end

  describe "validations" do
    it "is invalid with a negative home score" do
      expect(build(:match, home_score: -1)).not_to be_valid
    end

    it "is invalid with a negative away score" do
      expect(build(:match, away_score: -1)).not_to be_valid
    end

    it "rejects an advancing_team that did not play in the match" do
      match = create(:match, :knockout)
      outsider = create(:team, tournament: match.tournament)
      match.advancing_team = outsider

      expect(match).not_to be_valid
      expect(match.errors[:advancing_team_id]).to be_present
    end

    it "rejects an advancing_team during the group stage" do
      match = create(:match)
      match.advancing_team = match.home_team

      expect(match).not_to be_valid
      expect(match.errors[:advancing_team_id]).to be_present
    end

    it "accepts a participant advancing_team in a knockout phase" do
      match = create(:match, :knockout)
      match.advancing_team = match.away_team

      expect(match).to be_valid
    end
  end

  describe "the home/away team check constraint" do
    it "cannot be persisted with the same team as home and away" do
      team = create(:team)
      match = build(:match, tournament: team.tournament, home_team: team, away_team: team)

      expect { match.save! }.to raise_error(ActiveRecord::StatementInvalid)
    end
  end

  describe "#original_kickoff_at" do
    it "is set from kickoff_at on create" do
      kickoff = 3.days.from_now.change(usec: 0)
      match = create(:match, kickoff_at: kickoff)

      expect(match.original_kickoff_at).to be_within(1.second).of(kickoff)
    end
  end
end
