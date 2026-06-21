# frozen_string_literal: true

require "rails_helper"

RSpec.describe BracketBuildJob do
  it "runs on the :sync queue" do
    expect(described_class.queue_name).to eq("sync")
  end

  describe "#perform" do
    it "builds the bracket topology for the current tournament and logs the counts" do
      tournament = create(:tournament)
      allow(CurrentTournamentQuery).to receive(:call).and_return(tournament)
      allow(Brackets::BuildTopology).to receive(:call)
        .and_return(ServiceResult.new(data: { edges: 3, positions: 4 }))
      allow(Rails.logger).to receive(:info)

      described_class.perform_now

      expect(Brackets::BuildTopology).to have_received(:call).with(tournament: tournament)
      expect(Rails.logger).to have_received(:info).with(/edges=3 positions=4/)
    end

    it "skips when there is no current tournament" do
      allow(CurrentTournamentQuery).to receive(:call).and_return(nil)
      allow(Brackets::BuildTopology).to receive(:call)

      described_class.perform_now

      expect(Brackets::BuildTopology).not_to have_received(:call)
    end

    it "logs and does not re-raise when the build fails" do
      allow(CurrentTournamentQuery).to receive(:call).and_return(create(:tournament))
      allow(Brackets::BuildTopology).to receive(:call).and_return(ServiceResult.new(errors: [ "boom" ]))
      allow(Rails.logger).to receive(:error)

      expect { described_class.perform_now }.not_to raise_error
      expect(Rails.logger).to have_received(:error).with(/boom/)
    end
  end
end
