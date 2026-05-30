# frozen_string_literal: true

require "rails_helper"

RSpec.describe FootballData::Client do
  subject(:client) { described_class.new(sleeper: sleeper) }

  let(:base)    { "https://api.football-data.org/v4" }
  let(:api_key) { "test-token" }
  let(:cache)   { ActiveSupport::Cache::MemoryStore.new }
  let(:sleeper) { instance_spy(Proc) }
  let(:json_headers) { { "Content-Type" => "application/json" } }

  around do |example|
    original = ENV["FOOTBALL_DATA_API_KEY"]
    ENV["FOOTBALL_DATA_API_KEY"] = api_key
    example.run
    ENV["FOOTBALL_DATA_API_KEY"] = original
  end

  before do
    # Test env uses a null_store; swap in a real store so the rate-limit counter
    # and response cache actually behave. The sleeper is an injected spy, so the
    # rate limiter never blocks for real.
    allow(Rails).to receive(:cache).and_return(cache)
  end

  describe "#competition" do
    it "GETs the competition with the X-Auth-Token header and returns the parsed body" do
      stub = stub_request(:get, "#{base}/competitions/WC")
        .with(headers: { "X-Auth-Token" => api_key })
        .to_return(status: 200, body: { "id" => 2000, "code" => "WC" }.to_json, headers: json_headers)

      result = client.competition("WC")

      expect(result).to include("id" => 2000, "code" => "WC")
      expect(stub).to have_been_requested
    end
  end

  describe "#competition_teams" do
    it "GETs the teams sub-resource" do
      stub_request(:get, "#{base}/competitions/WC/teams")
        .to_return(status: 200, body: { "teams" => [] }.to_json, headers: json_headers)

      expect(client.competition_teams("WC")).to eq("teams" => [])
    end
  end

  describe "#competition_matches" do
    it "passes filters as query parameters" do
      stub = stub_request(:get, "#{base}/competitions/WC/matches")
        .with(query: { "matchday" => "1" })
        .to_return(status: 200, body: { "matches" => [] }.to_json, headers: json_headers)

      client.competition_matches("WC", filters: { matchday: 1 })

      expect(stub).to have_been_requested
    end
  end

  describe "#match" do
    it "GETs a single match by id" do
      stub_request(:get, "#{base}/matches/42")
        .to_return(status: 200, body: { "id" => 42 }.to_json, headers: json_headers)

      expect(client.match(42)).to eq("id" => 42)
    end
  end

  describe "error handling" do
    it "raises FootballData::ApiError on a non-2xx response" do
      stub_request(:get, "#{base}/competitions/WC").to_return(status: 403, body: "forbidden")

      expect { client.competition("WC") }
        .to raise_error(FootballData::ApiError, /failed/) { |e| expect(e.status).to eq(403) }
    end
  end

  describe "response caching" do
    it "serves repeat reads from cache within the TTL, hitting the network once" do
      stub = stub_request(:get, "#{base}/matches/7")
        .to_return(status: 200, body: { "id" => 7 }.to_json, headers: json_headers)

      2.times { client.match(7) }

      expect(stub).to have_been_requested.once
    end
  end

  describe "rate limiting" do
    it "pauses once the 60s window is saturated (the 11th distinct request)" do
      (1..11).each do |id|
        stub_request(:get, "#{base}/matches/#{id}")
          .to_return(status: 200, body: { "id" => id }.to_json, headers: json_headers)
      end

      (1..11).each { |id| client.match(id) }

      expect(sleeper).to have_received(:call).once
    end

    it "does not pause while under the limit" do
      (1..10).each do |id|
        stub_request(:get, "#{base}/matches/#{id}")
          .to_return(status: 200, body: { "id" => id }.to_json, headers: json_headers)
      end

      (1..10).each { |id| client.match(id) }

      expect(sleeper).not_to have_received(:call)
    end
  end
end
