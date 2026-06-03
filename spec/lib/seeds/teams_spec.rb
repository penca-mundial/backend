# frozen_string_literal: true

require "rails_helper"

# Seed modules live under db/seeds and are not autoloaded; load them directly.
require Rails.root.join("db/seeds/tournament").to_s
require Rails.root.join("db/seeds/teams").to_s

# Seeds::Teams must reconcile by code3 so it stays a no-op regardless of whether
# football_data:bootstrap (FootballData::SyncFixtures) has already replaced the
# placeholder external_ids with the real numeric ids. Keying on the placeholder
# would insert a duplicate code3 and trip the (tournament_id, code3) unique index.
RSpec.describe Seeds::Teams do
  def base = "https://api.football-data.org/v4"
  def json_headers = { "Content-Type" => "application/json" }

  let(:seed_data) { described_class.load_data }

  # An API teams payload covering exactly the seeded code3s, with numeric ids and
  # API-flavoured names/crests — i.e. what bootstrap writes over the placeholders.
  let(:api_teams) do
    seed_data.map.with_index(1) do |attrs, i|
      { "id" => 1000 + i, "name" => "API #{attrs['name']}", "tla" => attrs["code3"],
        "crest" => "https://crest/#{attrs['code3']}.png", "squad" => [] }
    end
  end

  before do
    stub_request(:get, "#{base}/competitions/WC")
      .to_return(status: 200, headers: json_headers, body: {
        "name" => Seeds::Tournament::NAME,
        "currentSeason" => { "startDate" => "2026-06-11", "endDate" => "2026-07-19" }
      }.to_json)
    stub_request(:get, "#{base}/competitions/WC/teams")
      .to_return(status: 200, headers: json_headers, body: { "teams" => api_teams }.to_json)
    stub_request(:get, "#{base}/competitions/WC/matches")
      .to_return(status: 200, headers: json_headers, body: { "matches" => [] }.to_json)
  end

  def seed!
    Seeds::Tournament.call
    described_class.call
  end

  def bootstrap!
    FootballData::SyncFixtures.call
  end

  def seeded_name(code3)
    seed_data.find { |t| t["code3"] == code3 }.fetch("name")
  end

  it "is idempotent: seeding twice leaves exactly 48 teams" do
    seed!

    expect { seed! }.not_to change(Team, :count).from(48)
  end

  it "stays a no-op (no RecordNotUnique) when re-seeded after bootstrap" do
    seed!
    bootstrap!

    expect { seed! }.not_to raise_error
    expect(Team.count).to eq(48)

    # External ids keep the real numeric API ids; names keep the seed's curated ones.
    arg = Team.find_by!(code3: "ARG")
    expect(arg.external_id).not_to start_with("wc2026-")
    expect(arg.name).to eq(seeded_name("ARG"))
  end

  it "lets bootstrap overwrite seeded placeholders while the seed names win" do
    seed!
    bootstrap!

    expect(Team.count).to eq(48)
    expect(Team.where("external_id LIKE ?", "wc2026-%")).to be_empty
    expect(Team.pluck(:name)).to match_array(seed_data.map { |t| t["name"] })
    expect(Team.find_by!(code3: "ARG").flag_url).to eq("https://crest/ARG.png")
  end
end
