# frozen_string_literal: true

require "rails_helper"

RSpec.describe FootballData::SyncFixtures do
  subject(:result) { described_class.call }

  let!(:tournament) { create(:tournament) }
  let(:competition_body) do
    {
      "id" => 2000,
      "name" => "FIFA World Cup",
      "currentSeason" => { "startDate" => "2026-06-11", "endDate" => "2026-07-19" }
    }
  end
  let(:teams_body) do
    {
      "count" => 2,
      "teams" => [
        {
          "id" => 1, "name" => "Argentina", "tla" => "ARG", "crest" => "https://crest/arg.png",
          "squad" => [ { "id" => 101, "name" => "Lionel Messi" }, { "id" => 102, "name" => "Emiliano Martinez" } ]
        },
        {
          "id" => 2, "name" => "Brazil", "tla" => "BRA", "crest" => "https://crest/bra.png",
          "squad" => [ { "id" => 201, "name" => "Vinicius Junior" } ]
        }
      ]
    }
  end
  let(:matches_body) do
    {
      "matches" => [
        {
          "id" => 1001, "utcDate" => "2026-06-11T18:00:00Z", "status" => "SCHEDULED", "stage" => "GROUP_STAGE",
          "homeTeam" => { "id" => 1 }, "awayTeam" => { "id" => 2 },
          "score" => { "fullTime" => { "home" => nil, "away" => nil } }
        },
        {
          "id" => 1002, "utcDate" => "2026-07-19T18:00:00Z", "status" => "FINISHED", "stage" => "FINAL",
          "homeTeam" => { "id" => 1 }, "awayTeam" => { "id" => 2 },
          "score" => { "fullTime" => { "home" => 3, "away" => 1 } }
        },
        {
          "id" => 1003, "utcDate" => "2026-07-05T18:00:00Z", "status" => "SCHEDULED", "stage" => "SEMI_FINALS",
          "homeTeam" => { "id" => nil }, "awayTeam" => { "id" => 2 },
          "score" => { "fullTime" => { "home" => nil, "away" => nil } }
        }
      ]
    }
  end

  def base = "https://api.football-data.org/v4"
  def json_headers = { "Content-Type" => "application/json" }

  before do
    stub_request(:get, "#{base}/competitions/WC")
      .to_return(status: 200, body: competition_body.to_json, headers: json_headers)
    stub_request(:get, "#{base}/competitions/WC/teams")
      .to_return(status: 200, body: teams_body.to_json, headers: json_headers)
    stub_request(:get, "#{base}/competitions/WC/matches")
      .to_return(status: 200, body: matches_body.to_json, headers: json_headers)
  end

  it "populates teams, players and matches and returns the counts" do
    expect(result).to be_success
    # The semi-final has a TBD home team, so it is skipped (2 of 3 matches sync).
    expect(result.data).to eq(teams_synced: 2, players_synced: 3, matches_synced: 2)

    expect(Team.count).to eq(2)
    expect(Player.count).to eq(3)
    expect(Match.count).to eq(2)
  end

  it "stores team and player attributes from the feed" do
    result

    arg = Team.find_by(external_id: "1")
    expect(arg).to have_attributes(
      name: "Argentina", code3: "ARG", flag_url: "https://crest/arg.png", tournament: tournament
    )
    expect(arg.players.pluck(:name)).to contain_exactly("Lionel Messi", "Emiliano Martinez")
  end

  it "maps status and phase codes and scores onto the Match enums" do
    result

    group = Match.find_by(external_id: "1001")
    expect(group).to have_attributes(status: "scheduled", phase: "group_stage")

    final = Match.find_by(external_id: "1002")
    expect(final).to have_attributes(status: "finished", phase: "final", home_score: 3, away_score: 1)
  end

  it "refreshes the tournament info from the competition payload" do
    result

    expect(tournament.reload).to have_attributes(
      name: "FIFA World Cup",
      starts_at: Time.zone.parse("2026-06-11"),
      ends_at: Time.zone.parse("2026-07-19")
    )
  end

  it "is idempotent: running twice yields the same state with no duplicates" do
    described_class.call
    second = described_class.call

    expect(second).to be_success
    expect(second.data).to eq(teams_synced: 2, players_synced: 3, matches_synced: 2)
    expect([ Team.count, Player.count, Match.count ]).to eq([ 2, 3, 2 ])
  end

  it "keeps original_kickoff_at fixed across re-syncs even if kickoff moves" do
    described_class.call
    original = Match.find_by(external_id: "1001").original_kickoff_at

    moved = matches_body.deep_dup
    moved["matches"][0]["utcDate"] = "2026-06-12T20:00:00Z"
    stub_request(:get, "#{base}/competitions/WC/matches")
      .to_return(status: 200, body: moved.to_json, headers: json_headers)

    described_class.call
    match = Match.find_by(external_id: "1001")

    expect(match.kickoff_at).to eq(Time.zone.parse("2026-06-12T20:00:00Z"))
    expect(match.original_kickoff_at).to eq(original)
  end
end
