# frozen_string_literal: true

require "rails_helper"

# Seed modules live under db/seeds and are not autoloaded; load it directly.
require Rails.root.join("db/seeds/tournament").to_s

# Seeds::Tournament and FootballData::SyncFixtures both reconcile the tournament
# by external_code (its stable identity), so they converge on a SINGLE row in any
# run order — db:seed never duplicates the tournament a bootstrap already created,
# and vice versa (the regression behind SCRUM-274). The seed owns the curated
# name; bootstrap owns the API dates.
RSpec.describe Seeds::Tournament do
  def base = "https://api.football-data.org/v4"
  def json_headers = { "Content-Type" => "application/json" }

  before do
    # The API competition name differs from the curated seed name on purpose.
    stub_request(:get, "#{base}/competitions/WC")
      .to_return(status: 200, headers: json_headers, body: {
        "name" => "FIFA World Cup",
        "currentSeason" => { "startDate" => "2026-06-11", "endDate" => "2026-07-19" }
      }.to_json)
    stub_request(:get, "#{base}/competitions/WC/teams")
      .to_return(status: 200, headers: json_headers, body: { "teams" => [] }.to_json)
    stub_request(:get, "#{base}/competitions/WC/matches")
      .to_return(status: 200, headers: json_headers, body: { "matches" => [] }.to_json)
  end

  def seed! = described_class.call
  def bootstrap! = FootballData::SyncFixtures.call

  it "is idempotent: re-seeding never duplicates the tournament" do
    seed!

    expect { seed! }.not_to change(Tournament, :count).from(1)
    expect(Tournament.sole).to have_attributes(external_code: "WC", name: "FIFA World Cup 2026")
  end

  it "converges to one WC tournament with the curated name: seed then bootstrap" do
    seed!
    bootstrap!

    expect(Tournament.count).to eq(1)
    expect(Tournament.sole).to have_attributes(external_code: "WC", name: "FIFA World Cup 2026")
  end

  it "converges to one WC tournament with the curated name: bootstrap then seed" do
    bootstrap!
    expect(Tournament.sole.name).to eq("FIFA World Cup") # API name as the create fallback

    seed!

    expect(Tournament.count).to eq(1)
    expect(Tournament.sole).to have_attributes(external_code: "WC", name: "FIFA World Cup 2026")
  end

  it "stays a single tournament across repeated seed and bootstrap runs" do
    seed!
    bootstrap!
    seed!
    bootstrap!

    expect(Tournament.count).to eq(1)
    expect(Tournament.sole).to have_attributes(external_code: "WC", name: "FIFA World Cup 2026")
  end

  it "preserves the curated name after sync_competition_info overwrites nothing" do
    seed!
    bootstrap!

    expect(Tournament.sole.name).to eq("FIFA World Cup 2026")
  end

  it "is the tournament CurrentTournamentQuery resolves" do
    seed!

    expect(CurrentTournamentQuery.call).to eq(Tournament.sole)
    expect(CurrentTournamentQuery.call.external_code).to eq("WC")
  end

  # Home renders a "Día N de M" progress label spanning starts_at..ends_at, so
  # the current tournament must carry a non-null ends_at (after starts_at).
  it "gives the current tournament a populated date span (starts_at < ends_at)" do
    seed!

    tournament = CurrentTournamentQuery.call
    expect(tournament.starts_at).to be_present
    expect(tournament.ends_at).to be_present
    expect(tournament.ends_at).to be > tournament.starts_at
  end
end
