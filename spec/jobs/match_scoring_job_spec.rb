# frozen_string_literal: true

require "rails_helper"

RSpec.describe MatchScoringJob do
  it "runs on the :scoring queue" do
    expect(described_class.queue_name).to eq("scoring")
  end

  describe "#perform" do
    let(:match) { create(:match, :finished) }

    it "calls ComputeMatchScores with the loaded match and logs the count on success" do
      allow(Scoring::ComputeMatchScores).to receive(:call).and_return(ServiceResult.new(data: { count: 3 }))
      allow(Rails.logger).to receive(:info)

      described_class.perform_now(match.id)

      expect(Scoring::ComputeMatchScores).to have_received(:call).with(match: match)
      expect(Rails.logger).to have_received(:info).with(/scored 3 prediction/)
    end

    it "logs the errors and does not re-raise when scoring fails" do
      allow(Scoring::ComputeMatchScores).to receive(:call).and_return(ServiceResult.new(errors: [ "boom" ]))
      allow(Rails.logger).to receive(:error)

      expect { described_class.perform_now(match.id) }.not_to raise_error
      expect(Rails.logger).to have_received(:error).with(/boom/)
    end

    it "discards without raising when the match does not exist" do
      allow(Scoring::ComputeMatchScores).to receive(:call)

      expect { described_class.perform_now(0) }.not_to raise_error
      expect(Scoring::ComputeMatchScores).not_to have_received(:call)
    end
  end
end
