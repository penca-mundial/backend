# frozen_string_literal: true

require "rails_helper"

RSpec.describe TournamentScoringJob do
  it "runs on the :scoring queue" do
    expect(described_class.queue_name).to eq("scoring")
  end

  describe "#perform" do
    let(:tournament) { create(:tournament) }

    it "calls ComputeTournamentScores with the loaded tournament and logs the count on success" do
      allow(Scoring::ComputeTournamentScores).to receive(:call).and_return(ServiceResult.new(data: { count: 7 }))
      allow(Rails.logger).to receive(:info)

      described_class.perform_now(tournament.id)

      expect(Scoring::ComputeTournamentScores).to have_received(:call).with(tournament: tournament)
      expect(Rails.logger).to have_received(:info).with(/scored 7 prediction/)
    end

    it "logs the errors and does not re-raise when scoring fails" do
      allow(Scoring::ComputeTournamentScores).to receive(:call).and_return(ServiceResult.new(errors: [ "boom" ]))
      allow(Rails.logger).to receive(:error)

      expect { described_class.perform_now(tournament.id) }.not_to raise_error
      expect(Rails.logger).to have_received(:error).with(/boom/)
    end

    it "discards without raising when the tournament does not exist" do
      allow(Scoring::ComputeTournamentScores).to receive(:call)

      expect { described_class.perform_now(0) }.not_to raise_error
      expect(Scoring::ComputeTournamentScores).not_to have_received(:call)
    end
  end
end
