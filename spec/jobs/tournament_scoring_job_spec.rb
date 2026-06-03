# frozen_string_literal: true

require "rails_helper"

RSpec.describe TournamentScoringJob do
  include ActiveJob::TestHelper

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

    it "logs and retries (does not complete silently) when scoring fails" do
      allow(Scoring::ComputeTournamentScores).to receive(:call).and_return(ServiceResult.new(errors: [ "boom" ]))
      allow(Rails.logger).to receive(:error)

      # retry_on catches the re-raised failure on this attempt and enqueues a
      # retry, rather than the job completing as if nothing went wrong.
      expect { described_class.perform_now(tournament.id) }
        .to have_enqueued_job(described_class).with(tournament.id)
      expect(Rails.logger).to have_received(:error).with(/boom/)
    end

    it "re-raises the failure once retries are exhausted" do
      allow(Scoring::ComputeTournamentScores).to receive(:call).and_return(ServiceResult.new(errors: [ "boom" ]))
      allow(Rails.logger).to receive(:error)

      # On the final attempt retry_on gives up and the error surfaces, so the
      # job lands in failed jobs instead of disappearing.
      expect { perform_enqueued_jobs { described_class.perform_now(tournament.id) } }
        .to raise_error(/boom/)
    end

    it "discards without raising when the tournament does not exist" do
      allow(Scoring::ComputeTournamentScores).to receive(:call)

      expect { described_class.perform_now(0) }.not_to raise_error
      expect(Scoring::ComputeTournamentScores).not_to have_received(:call)
    end
  end
end
