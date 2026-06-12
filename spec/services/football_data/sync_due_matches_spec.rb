# frozen_string_literal: true

require "rails_helper"

RSpec.describe FootballData::SyncDueMatches do
  include ActiveSupport::Testing::TimeHelpers

  # A client whose #match always raises, simulating a 429 / network failure from
  # football-data.org for the polled match — the SCRUM-313 "dead window" where
  # the worker's fetch failed every tick while last_synced_at stayed frozen.
  let(:failing_client) do
    instance_double(FootballData::Client).tap do |client|
      allow(client).to receive(:match)
        .and_raise(FootballData::ApiError.new("rate limited", status: 429))
    end
  end

  describe "a single match failing to sync" do
    let!(:match) do
      create(:match, :live, external_id: "live-1", kickoff_at: 30.minutes.ago, last_synced_at: 2.hours.ago)
    end

    it "logs the failing match id and the error (no more silent failures)" do
      allow(Rails.logger).to receive(:warn)

      described_class.call(client: failing_client)

      expect(Rails.logger).to have_received(:warn)
        .with(a_string_including(match.id.to_s).and(a_string_including("rate limited")))
    end

    it "does not advance last_synced_at when the sync fails" do
      frozen = match.last_synced_at

      described_class.call(client: failing_client)

      expect(match.reload.last_synced_at).to eq(frozen)
    end

    it "reports the failure in the result instead of counting it as synced" do
      result = described_class.call(client: failing_client)

      expect(result).to be_success
      expect(result.data).to include(synced: 0, failed: 1)
    end
  end

  it "keeps syncing the rest of the batch after one match fails" do
    create(:match, :live, external_id: "live-ok", kickoff_at: 30.minutes.ago)
    create(:match, :live, external_id: "live-bad", kickoff_at: 20.minutes.ago)

    partial_client = instance_double(FootballData::Client)
    allow(partial_client).to receive(:match).with("live-ok", any_args)
      .and_return("status" => "IN_PLAY", "score" => { "fullTime" => { "home" => 1, "away" => 0 } })
    allow(partial_client).to receive(:match).with("live-bad", any_args)
      .and_raise(FootballData::ApiError.new("boom", status: 500))

    result = described_class.call(client: partial_client)

    expect(result.data).to include(synced: 1, failed: 1)
  end
end
