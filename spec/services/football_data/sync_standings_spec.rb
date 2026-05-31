# frozen_string_literal: true

require "rails_helper"

RSpec.describe FootballData::SyncStandings do
  def base = "https://api.football-data.org/v4"
  def json_headers = { "Content-Type" => "application/json" }

  def stub_standings(code, body)
    stub_request(:get, "#{base}/competitions/#{code}/standings")
      .to_return(status: 200, body: body.to_json, headers: json_headers)
  end

  # One row in a group table, keyed by the team's external id.
  def row(team_external_id, position:, points:, **extra)
    {
      "position" => position,
      "team" => { "id" => team_external_id.to_i },
      "playedGames" => 3, "won" => 2, "draw" => 1, "lost" => 0,
      "goalsFor" => 5, "goalsAgainst" => 2, "goalDifference" => 3,
      "points" => points, "form" => "W,W,D"
    }.merge(extra)
  end

  # A World Cup tournament with four teams whose external_ids match the feed.
  let(:tournament) { create(:tournament, external_code: "WC") }
  let(:wc_body) do
    {
      "standings" => [
        {
          "stage" => "GROUP_STAGE", "type" => "TOTAL", "group" => "GROUP_A",
          "table" => [ row("1", position: 1, points: 9), row("2", position: 2, points: 6) ]
        },
        {
          "stage" => "GROUP_STAGE", "type" => "TOTAL", "group" => "GROUP_B",
          "table" => [ row("3", position: 1, points: 7), row("4", position: 2, points: 4) ]
        }
      ]
    }
  end

  before do
    %w[1 2 3 4].each { |id| create(:team, tournament: tournament, external_id: id) }
  end

  it "upserts one row per team and returns the count" do
    stub_standings("WC", wc_body)

    result = described_class.call(tournament: tournament)

    expect(result).to be_success
    expect(result.data).to eq(standings_synced: 4)
    expect(tournament.standings.count).to eq(4)
  end

  it "mirrors the upstream fields and normalizes the group letter" do
    stub_standings("WC", wc_body)
    described_class.call(tournament: tournament)

    leader = tournament.standings.find_by(team: Team.find_by(external_id: "1"))
    expect(leader).to have_attributes(
      group: "A", position: 1, points: 9, played_games: 3, won: 2, draw: 1, lost: 0,
      goals_for: 5, goals_against: 2, goal_difference: 3, form: "W,W,D"
    )
    expect(tournament.standings.pluck(:group).uniq).to contain_exactly("A", "B")
  end

  it "ignores HOME/AWAY split tables, syncing only the TOTAL table" do
    body = {
      "standings" => [
        { "type" => "TOTAL", "group" => "GROUP_A", "table" => [ row("1", position: 1, points: 9) ] },
        { "type" => "HOME",  "group" => "GROUP_A", "table" => [ row("1", position: 1, points: 6) ] },
        { "type" => "AWAY",  "group" => "GROUP_A", "table" => [ row("1", position: 1, points: 3) ] }
      ]
    }
    stub_standings("WC", body)

    result = described_class.call(tournament: tournament)

    expect(result.data).to eq(standings_synced: 1)
    expect(tournament.standings.sole.points).to eq(9) # from TOTAL, not HOME/AWAY
  end

  it "skips rows whose team is not in our database" do
    body = {
      "standings" => [
        { "type" => "TOTAL", "group" => "GROUP_A",
          "table" => [ row("1", position: 1, points: 9), row("999", position: 2, points: 6) ] }
      ]
    }
    stub_standings("WC", body)

    result = described_class.call(tournament: tournament)

    expect(result.data).to eq(standings_synced: 1)
  end

  it "stores no rows for a competition with only knockout (group-less) tables" do
    body = { "standings" => [ { "type" => "TOTAL", "group" => nil, "table" => [ row("1", position: 1, points: 9) ] } ] }
    stub_standings("WC", body)

    result = described_class.call(tournament: tournament)

    expect(result.data).to eq(standings_synced: 0)
    expect(tournament.standings).to be_empty
  end

  it "is idempotent: re-running updates rows in place without duplicating" do
    stub_standings("WC", wc_body)
    described_class.call(tournament: tournament)

    # Argentina climbs to 9 -> still leader; feed updates the points.
    updated = wc_body.deep_dup
    updated["standings"][0]["table"][1]["points"] = 7 # team 2: 6 -> 7
    stub_standings("WC", updated)

    expect { described_class.call(tournament: tournament) }.not_to change(Standing, :count)
    expect(tournament.standings.find_by(team: Team.find_by(external_id: "2")).points).to eq(7)
  end

  it "fails cleanly when the tournament has no external_code" do
    codeless = create(:tournament, external_code: nil)

    result = described_class.call(tournament: codeless)

    expect(result).to be_failure
    expect(result.errors.join).to match(/external_code/)
  end

  it "returns a failed result when the upstream API errors" do
    stub_request(:get, "#{base}/competitions/WC/standings").to_return(status: 500, body: "boom")

    result = described_class.call(tournament: tournament)

    expect(result).to be_failure
    expect(tournament.standings).to be_empty # transaction rolled back
  end

  # EXTENSIBILITY: the exact same code syncs a different competition with a
  # different code and a group label OUTSIDE A-L, with no changes.
  context "with a non-World-Cup tournament" do
    let(:champions_league) { create(:tournament, external_code: "CL") }

    before do
      %w[50 51].each { |id| create(:team, tournament: champions_league, external_id: id) }
    end

    it "syncs standings for any tournament/competition code, including non-A-L groups" do
      stub_standings("CL", {
        "standings" => [
          { "type" => "TOTAL", "group" => "GROUP_M",
            "table" => [ row("50", position: 1, points: 12), row("51", position: 2, points: 9) ] }
        ]
      })

      result = described_class.call(tournament: champions_league)

      expect(result.data).to eq(standings_synced: 2)
      expect(champions_league.standings.pluck(:group).uniq).to eq([ "M" ]) # label beyond A-L preserved
      # Scoped strictly to this tournament — the WC tournament is untouched.
      expect(tournament.standings).to be_empty
    end
  end
end
