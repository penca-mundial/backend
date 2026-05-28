# frozen_string_literal: true

require "rails_helper"

# Cross-model paper_trail integration: every tracked model writes a version on
# update; User restricts tracking to admin/banned_at; the controller-configured
# whodunnit lands on the version row.
RSpec.describe "PaperTrail integration", type: :model do
  describe "tracked models" do
    it "records a version when a Match is updated" do
      match = create(:match)

      expect { match.update!(kickoff_at: 2.days.from_now) }
        .to change { PaperTrail::Version.where(item: match).count }.by(1)
    end

    it "records a version when a Prediction is updated" do
      prediction = create(:prediction)

      expect { prediction.update!(predicted_home_score: prediction.predicted_home_score + 1) }
        .to change { PaperTrail::Version.where(item: prediction).count }.by(1)
    end

    it "records a version when a TournamentPrediction is updated" do
      tp = create(:tournament_prediction)

      expect { tp.update!(locked_at: Time.current) }
        .to change { PaperTrail::Version.where(item: tp).count }.by(1)
    end

    it "records a version when a ScoringRule is updated" do
      rule = create(:scoring_rule)

      expect { rule.update!(points: rule.points + 1) }
        .to change { PaperTrail::Version.where(item: rule).count }.by(1)
    end

    it "records a version when a PhaseMultiplier is updated" do
      pm = create(:phase_multiplier)

      expect { pm.update!(multiplier: 2.5) }
        .to change { PaperTrail::Version.where(item: pm).count }.by(1)
    end

    it "records a version when a Group is updated" do
      group = create(:group)

      expect { group.update!(name: "Renamed group") }
        .to change { PaperTrail::Version.where(item: group).count }.by(1)
    end
  end

  describe "User (restricted tracking)" do
    let(:user) { create(:user) }

    it "does not record a version when the username changes" do
      expect { user.update!(username: "renamed_user") }
        .not_to change { PaperTrail::Version.where(item: user).count }
    end

    it "records a version when admin flips" do
      expect { user.update!(admin: true) }
        .to change { PaperTrail::Version.where(item: user).count }.by(1)
    end

    it "records a version when banned_at is set" do
      expect { user.update!(banned_at: Time.current) }
        .to change { PaperTrail::Version.where(item: user).count }.by(1)
    end
  end

  describe "whodunnit propagation" do
    it "captures the request-scoped whodunnit on the version" do
      match = nil

      PaperTrail.request(whodunnit: "42") do
        match = create(:match)
        match.update!(kickoff_at: 2.days.from_now)
      end

      expect(match.versions.last.whodunnit).to eq("42")
    end
  end
end
