# frozen_string_literal: true

require "rails_helper"

RSpec.describe "GET /api/v1/tournaments/:id/standings" do
  include ActiveSupport::Testing::TimeHelpers

  let(:tournament) { create(:tournament) }

  def get_standings
    get "/api/v1/tournaments/#{tournament.id}/standings"
  end

  it "returns each group with its ranked, computed standings" do
    argentina = create(:team, tournament: tournament, name: "Argentina")
    brazil    = create(:team, tournament: tournament, name: "Brazil")
    create(:match, tournament: tournament, phase: "group_stage", group: "A",
                   home_team: argentina, away_team: brazil,
                   status: "finished", home_score: 2, away_score: 0)

    get_standings

    expect(response).to have_http_status(:ok)
    group_a = response.parsed_body.find { |g| g["name"] == "A" }
    leader = group_a["standings"].first
    expect(leader).to include(
      "position" => 1, "played" => 1, "won" => 1, "drawn" => 0, "lost" => 0,
      "goals_for" => 2, "goals_against" => 0, "goal_difference" => 2, "points" => 3
    )
    expect(leader["team"]).to include("name" => "Argentina", "code3" => argentina.code3)
  end

  # Mirrors the auth policy of the GET /api/v1/standings feed (SCRUM-262) it will
  # replace, so the front-end swap is transparent. 262 is public, so this is too.
  it "is publicly accessible without authentication" do
    get_standings

    expect(response).to have_http_status(:ok)
    expect(response).not_to have_http_status(:unauthorized)
  end

  it "404s when the tournament does not exist" do
    get "/api/v1/tournaments/0/standings"

    expect(response).to have_http_status(:not_found)
  end

  describe "caching (short TTL dedupes the SPA polling)" do
    let(:cache) { ActiveSupport::Cache::MemoryStore.new }

    before { allow(Rails).to receive(:cache).and_return(cache) }

    it "serves a cached body within the TTL and recomputes after it expires" do
      allow(GroupStandingsQuery).to receive(:call).and_call_original

      get_standings
      get_standings
      expect(GroupStandingsQuery).to have_received(:call).once # second request is a cache hit

      travel(Api::V1::Tournaments::StandingsController::CACHE_TTL + 1.second) do
        get_standings
      end
      expect(GroupStandingsQuery).to have_received(:call).twice # recomputed after the TTL
    end
  end

  it "does not issue an N+1 for the embedded teams" do
    3.times do |i|
      create(:match, tournament: tournament, phase: "group_stage", group: "A",
                     home_team: create(:team, tournament: tournament),
                     away_team: create(:team, tournament: tournament),
                     status: "finished", home_score: 1, away_score: 0)
    end

    query_count = 0
    counter = lambda do |_name, _started, _finished, _id, payload|
      query_count += 1 unless %w[SCHEMA TRANSACTION].include?(payload[:name])
    end

    ActiveSupport::Notifications.subscribed(counter, "sql.active_record") do
      get_standings
    end

    # Resolve the tournament, load matches, preload both team sides; bounded and
    # independent of the number of matches/teams.
    expect(query_count).to be <= 5
  end
end
