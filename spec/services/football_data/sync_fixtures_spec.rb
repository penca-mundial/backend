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
          "group" => "GROUP_A",
          "homeTeam" => { "id" => 1 }, "awayTeam" => { "id" => 2 },
          "score" => { "fullTime" => { "home" => nil, "away" => nil } }
        },
        {
          "id" => 1002, "utcDate" => "2026-07-19T18:00:00Z", "status" => "FINISHED", "stage" => "FINAL",
          "group" => nil,
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

  it "normalizes the group letter for group-stage matches and leaves knockout matches nil" do
    result

    expect(Match.find_by(external_id: "1001").group).to eq("A") # "GROUP_A" -> "A"
    expect(Match.find_by(external_id: "1002").group).to be_nil  # knockout: no group
  end

  it "keeps the group stable across re-syncs (idempotent)" do
    described_class.call
    described_class.call

    expect(Match.find_by(external_id: "1001").group).to eq("A")
  end

  it "refreshes the tournament info from the competition payload" do
    result

    expect(tournament.reload).to have_attributes(
      name: "FIFA World Cup",
      starts_at: Time.zone.parse("2026-06-11"),
      ends_at: Time.zone.parse("2026-07-19")
    )
  end

  it "syncs the current tournament (resolver), not the first by id" do
    # `tournament` (let!) is upcoming and first-by-id; an active one outranks it
    # in CurrentTournamentQuery, so the sync must target the active one.
    active = create(:tournament, starts_at: 1.day.ago, ends_at: 1.month.from_now, name: "Active Cup")

    described_class.call

    expect(active.reload.name).to eq("FIFA World Cup")          # competition payload synced here
    expect(tournament.reload.name).not_to eq("FIFA World Cup")  # the first-by-id one is untouched
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

  context "with teams already created by db:seed (placeholder external_id)" do
    # Mirrors db/seeds/teams.rb: code3 is the real key, external_id is a
    # placeholder and the name is the curated Spanish translation.
    let!(:seeded_argentina) do
      create(:team, tournament: tournament, code3: "ARG", external_id: "wc2026-arg", name: "Argentina")
    end

    it "reconciles the seeded team in place instead of raising PG::UniqueViolation" do
      expect { described_class.call }.not_to raise_error

      expect(Team.where(code3: "ARG").count).to eq(1)
      expect(seeded_argentina.reload).to have_attributes(
        external_id: "1",                       # placeholder overwritten with API id
        flag_url: "https://crest/arg.png",      # set from the API
        name: "Argentina"                       # preserved from the seed
      )
    end

    it "preserves the seed's curated name even when the API name differs" do
      seeded_argentina.update!(name: "Argentina (curado)")

      described_class.call

      expect(seeded_argentina.reload.name).to eq("Argentina (curado)")
      expect(seeded_argentina.external_id).to eq("1")
    end

    it "stays idempotent across repeated syncs" do
      described_class.call
      expect { described_class.call }.not_to raise_error

      expect(Team.where(code3: "ARG").count).to eq(1)
      expect(Team.count).to eq(2) # Argentina (reconciled) + Brazil (created)
    end
  end

  describe "knockout result and advancing team" do
    def stub_matches(body)
      stub_request(:get, "#{base}/competitions/WC/matches")
        .to_return(status: 200, body: body.to_json, headers: json_headers)
    end

    it "stores the 90' result (regularTime) and the advancing team from winner" do
      stub_matches("matches" => [
        { "id" => 1004, "utcDate" => "2026-07-10T18:00:00Z", "status" => "FINISHED", "stage" => "LAST_16",
          "homeTeam" => { "id" => 1 }, "awayTeam" => { "id" => 2 },
          "score" => { "regularTime" => { "home" => 1, "away" => 1 },
                       "fullTime" => { "home" => 7, "away" => 6 }, "winner" => "HOME_TEAM" } }
      ])

      described_class.call

      argentina = Team.find_by(external_id: "1")
      expect(Match.find_by(external_id: "1004")).to have_attributes(
        phase: "round_of_16", home_score: 1, away_score: 1, advancing_team_id: argentina.id
      )
    end

    it "leaves advancing_team_id nil (without raising) for a finished KO with no clear winner" do
      stub_matches("matches" => [
        { "id" => 1005, "utcDate" => "2026-07-10T18:00:00Z", "status" => "FINISHED", "stage" => "LAST_16",
          "homeTeam" => { "id" => 1 }, "awayTeam" => { "id" => 2 },
          "score" => { "fullTime" => { "home" => 1, "away" => 1 }, "winner" => "DRAW" } }
      ])

      expect { described_class.call }.not_to raise_error
      expect(Match.find_by(external_id: "1005").advancing_team_id).to be_nil
    end

    it "leaves advancing_team_id nil for a group-stage match" do
      described_class.call # default body: match 1001 is GROUP_STAGE

      expect(Match.find_by(external_id: "1001").advancing_team_id).to be_nil
    end
  end

  describe "incremental re-sync (create-on-resolve)" do
    def stub_matches(body)
      stub_request(:get, "#{base}/competitions/WC/matches")
        .to_return(status: 200, body: body.to_json, headers: json_headers)
    end

    # Teams already exist in the DB (qualified from the group stage); the
    # incremental pass reads them from the DB, not the API.
    before do
      create(:team, tournament: tournament, external_id: "1", code3: "ARG")
      create(:team, tournament: tournament, external_id: "2", code3: "BRA")
    end

    def team(external_id) = Team.find_by!(external_id: external_id)

    it "creates a knockout match once the feed names both teams" do
      stub_matches("matches" => [
        { "id" => 2001, "utcDate" => "2026-06-28T19:00:00Z", "status" => "TIMED", "stage" => "LAST_16",
          "homeTeam" => { "id" => 1 }, "awayTeam" => { "id" => 2 }, "score" => { "winner" => nil } }
      ])

      result = described_class.call(incremental: true)

      expect(result).to be_success
      expect(result.data).to eq(matches_created: 1)
      expect(Match.find_by(external_id: "2001")).to have_attributes(
        phase: "round_of_16", status: "scheduled",
        home_team_id: team("1").id, away_team_id: team("2").id
      )
    end

    it "skips a knockout match whose teams are still TBD in the feed" do
      stub_matches("matches" => [
        { "id" => 2002, "utcDate" => "2026-06-28T19:00:00Z", "status" => "TIMED", "stage" => "LAST_16",
          "homeTeam" => { "id" => nil }, "awayTeam" => { "id" => nil }, "score" => { "winner" => nil } }
      ])

      result = described_class.call(incremental: true)

      expect(result.data).to eq(matches_created: 0)
      expect(Match.find_by(external_id: "2002")).to be_nil
    end

    it "is idempotent: re-running does not re-create the match" do
      stub_matches("matches" => [
        { "id" => 2001, "utcDate" => "2026-06-28T19:00:00Z", "status" => "TIMED", "stage" => "LAST_16",
          "homeTeam" => { "id" => 1 }, "awayTeam" => { "id" => 2 }, "score" => { "winner" => nil } }
      ])

      described_class.call(incremental: true)
      expect { described_class.call(incremental: true) }.not_to change(Match, :count)
      expect(described_class.call(incremental: true).data).to eq(matches_created: 0)
    end

    it "never clobbers the live state of an existing match (only refreshes inert kickoff_at)" do
      existing = create(:match, :finished, external_id: "1001", tournament: tournament,
                                            home_team: team("1"), away_team: team("2"),
                                            home_score: 2, away_score: 1, minute: 90,
                                            kickoff_at: Time.zone.parse("2026-06-11T18:00:00Z"))
      existing.update!(events_log: [ { "minute" => 23 } ])

      # Feed reports different (live) values + a moved kickoff. Only kickoff_at
      # may change; the rest is SyncMatch's domain.
      stub_matches("matches" => [
        { "id" => 1001, "utcDate" => "2026-06-11T20:00:00Z", "status" => "IN_PLAY", "stage" => "GROUP_STAGE",
          "homeTeam" => { "id" => 1 }, "awayTeam" => { "id" => 2 },
          "score" => { "fullTime" => { "home" => 9, "away" => 9 }, "winner" => "HOME_TEAM" } }
      ])

      expect { described_class.call(incremental: true) }.not_to change(Match, :count)

      existing.reload
      expect(existing).to have_attributes(
        status: "finished", home_score: 2, away_score: 1, advancing_team_id: nil, minute: 90
      )
      expect(existing.events_log).to eq([ { "minute" => 23 } ])
      expect(existing.kickoff_at).to eq(Time.zone.parse("2026-06-11T20:00:00Z")) # inert metadata refreshed
    end
  end
end
