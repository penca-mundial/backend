# frozen_string_literal: true

require "rails_helper"

# rubocop:disable RSpec/DescribeClass
RSpec.describe "Api::V1::PlayersController", type: :request do
  # rubocop:enable RSpec/DescribeClass
  let(:headers) { { "User-Agent" => "rspec" } }
  let(:tournament) { create(:tournament, starts_at: 1.day.ago, ends_at: 1.week.from_now) }

  describe "GET /api/v1/players" do
    it "returns the current tournament's players, paginated and ordered by name, publicly" do
      team = create(:team, tournament: tournament)
      create(:player, team: team, name: "Zoe", external_id: "p-zoe")
      create(:player, team: team, name: "Aaron")

      get "/api/v1/players", headers: headers

      expect(response).to have_http_status(:ok)
      body = response.parsed_body
      expect(body.map { |p| p["name"] }).to eq(%w[Aaron Zoe])
      expect(response.headers["X-Total-Count"]).to eq("2")
      expect(body.first).to include("id", "name" => "Aaron", "team_id" => team.id)
      expect(body.first).to have_key("external_id")
      expect(body.first["team"]).to include("id" => team.id, "name" => team.name, "code3" => team.code3)
    end

    it "filters by team_id" do
      team = create(:team, tournament: tournament)
      other = create(:team, tournament: tournament)
      mine = create(:player, team: team, name: "Mine")
      create(:player, team: other, name: "Other")

      get "/api/v1/players", params: { team_id: team.id }, headers: headers

      expect(response.parsed_body.map { |p| p["id"] }).to eq([ mine.id ])
    end

    it "filters by tournament_id through teams" do
      team = create(:team, tournament: tournament)
      mine = create(:player, team: team, name: "Mine")
      create(:player) # a player in some other tournament

      get "/api/v1/players", params: { tournament_id: tournament.id }, headers: headers

      expect(response.parsed_body.map { |p| p["id"] }).to eq([ mine.id ])
    end

    it "defaults to the current tournament (resolver), not the first by id" do
      past = create(:tournament, starts_at: 1.month.ago, ends_at: 1.week.ago) # lower id
      create(:player, team: create(:team, tournament: past), name: "OldPlayer")
      current_player = create(:player, team: create(:team, tournament: tournament), name: "CurrentPlayer")

      get "/api/v1/players", headers: headers

      expect(response.parsed_body.map { |p| p["id"] }).to eq([ current_player.id ])
    end

    it "paginates with ?per_page and exposes the total count" do
      team = create(:team, tournament: tournament)
      create_list(:player, 3, team: team)

      get "/api/v1/players", params: { per_page: 2 }, headers: headers

      expect(response.parsed_body.size).to eq(2)
      expect(response.headers["X-Total-Count"]).to eq("3")
    end

    it "404s on an invalid team_id" do
      get "/api/v1/players", params: { team_id: 0 }, headers: headers
      expect(response).to have_http_status(:not_found)
    end

    it "404s on an invalid tournament_id" do
      get "/api/v1/players", params: { tournament_id: 0 }, headers: headers
      expect(response).to have_http_status(:not_found)
    end

    it "404s when there are no tournaments at all" do
      get "/api/v1/players", headers: headers
      expect(response).to have_http_status(:not_found)
    end

    it "is N+1 free (query count independent of the number of players)" do
      team = create(:team, tournament: tournament)
      create_list(:player, 6, team: team)

      query_count = 0
      counter = lambda do |_name, _started, _finished, _id, payload|
        query_count += 1 unless %w[SCHEMA TRANSACTION].include?(payload[:name])
      end

      ActiveSupport::Notifications.subscribed(counter, "sql.active_record") do
        get "/api/v1/players", params: { tournament_id: tournament.id }, headers: headers
      end

      expect(query_count).to be <= 5
    end
  end
end
