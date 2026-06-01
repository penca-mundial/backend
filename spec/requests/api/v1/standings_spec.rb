# frozen_string_literal: true

require "rails_helper"

# rubocop:disable RSpec/DescribeClass
RSpec.describe "Api::V1::StandingsController", type: :request do
  # rubocop:enable RSpec/DescribeClass
  let(:headers) { { "User-Agent" => "rspec" } }
  let(:tournament) { create(:tournament) }

  describe "GET /api/v1/standings" do
    it "returns standings grouped by group letter, ordered by position, scoped to the tournament" do
      team_a1 = create(:team, tournament: tournament, name: "Argentina")
      create(:standing, tournament: tournament, team: team_a1, group: "A", position: 1, points: 9)
      create(:standing, tournament: tournament, group: "A", position: 2, points: 6)
      create(:standing, tournament: tournament, group: "B", position: 1, points: 7)
      create(:standing) # another tournament — must not leak in

      get "/api/v1/standings", params: { tournament_id: tournament.id }, headers: headers

      expect(response).to have_http_status(:ok)
      groups = response.parsed_body["groups"]
      expect(groups.keys).to eq(%w[A B])
      expect(groups["A"].map { |row| row["position"] }).to eq([ 1, 2 ])
      expect(groups["A"].first).to include("points" => 9, "group" => "A")
      expect(groups["A"].first["team"]).to include("id" => team_a1.id, "name" => "Argentina")
    end

    it "defaults to the current tournament when no tournament_id is given" do
      create(:standing, tournament: tournament, group: "C", position: 1)

      get "/api/v1/standings", headers: headers

      expect(response).to have_http_status(:ok)
      expect(response.parsed_body["groups"].keys).to eq(%w[C])
    end

    it "defaults to the current tournament (resolver), not the first by id" do
      past = create(:tournament, starts_at: 1.month.ago, ends_at: 1.week.ago)        # lower id
      current = create(:tournament, starts_at: 1.day.ago, ends_at: 1.week.from_now)  # active
      create(:standing, tournament: past, group: "Z", position: 1)
      create(:standing, tournament: current, group: "A", position: 1)

      get "/api/v1/standings", headers: headers

      expect(response).to have_http_status(:ok)
      expect(response.parsed_body["groups"].keys).to eq(%w[A]) # current's group, not past's "Z"
    end

    it "returns empty groups when the tournament has no standings" do
      get "/api/v1/standings", params: { tournament_id: tournament.id }, headers: headers

      expect(response).to have_http_status(:ok)
      expect(response.parsed_body["groups"]).to eq({})
    end

    it "is publicly accessible without authentication" do
      get "/api/v1/standings", params: { tournament_id: tournament.id }, headers: headers

      expect(response).to have_http_status(:ok)
    end

    it "404s when the requested tournament does not exist" do
      get "/api/v1/standings", params: { tournament_id: 0 }, headers: headers

      expect(response).to have_http_status(:not_found)
    end

    it "does not issue an N+1 for the embedded teams" do
      create_list(:standing, 6, tournament: tournament)

      query_count = 0
      counter = lambda do |_name, _started, _finished, _id, payload|
        query_count += 1 unless %w[SCHEMA TRANSACTION].include?(payload[:name])
      end

      ActiveSupport::Notifications.subscribed(counter, "sql.active_record") do
        get "/api/v1/standings", params: { tournament_id: tournament.id }, headers: headers
      end

      # Bounded and independent of the number of standings rows: resolve the
      # tournament, load standings, preload teams (+ a couple of framework
      # queries). Crucially does NOT grow with the row count.
      expect(query_count).to be <= 4
    end
  end
end
