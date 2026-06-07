# frozen_string_literal: true

require "rails_helper"

# rubocop:disable RSpec/DescribeClass
RSpec.describe "Api::V1::TeamsController", type: :request do
  # rubocop:enable RSpec/DescribeClass
  let(:headers) { { "User-Agent" => "rspec" } }

  describe "GET /api/v1/teams" do
    it "returns the tournament's PARTICIPATING teams ordered by name, serialized extended, publicly" do
      tournament = create(:tournament, starts_at: 1.day.ago, ends_at: 1.week.from_now)
      argentina = create(:team, tournament: tournament, name: "Argentina", code3: "ARG",
                                 flag_url: "http://x/arg.png", external_id: "ext-arg")
      brazil = create(:team, tournament: tournament, name: "Brazil")
      create(:match, tournament: tournament, home_team: argentina, away_team: brazil)
      create(:team, tournament: tournament, name: "Leftover") # tagged, no matches: excluded

      get "/api/v1/teams", params: { tournament_id: tournament.id }, headers: headers

      expect(response).to have_http_status(:ok)
      body = response.parsed_body
      expect(body.map { |t| t["name"] }).to eq(%w[Argentina Brazil])
      expect(body.first).to include(
        "id" => argentina.id, "name" => "Argentina", "code3" => "ARG",
        "flag_url" => "http://x/arg.png", "external_id" => "ext-arg",
        "tournament_id" => tournament.id
      )
    end

    it "defaults to the current tournament (resolver), not the first by id" do
      past = create(:tournament, starts_at: 1.month.ago, ends_at: 1.week.ago)        # lower id
      current = create(:tournament, starts_at: 1.day.ago, ends_at: 1.week.from_now)  # active
      old_team = create(:team, tournament: past, name: "OldTeam")
      create(:match, tournament: past, home_team: old_team)
      current_team = create(:team, tournament: current, name: "CurrentTeam")
      rival = create(:team, tournament: current, name: "RivalTeam")
      create(:match, tournament: current, home_team: current_team, away_team: rival)

      get "/api/v1/teams", headers: headers

      expect(response).to have_http_status(:ok)
      expect(response.parsed_body.map { |t| t["id"] }).to contain_exactly(current_team.id, rival.id)
    end

    it "404s when the requested tournament_id does not exist" do
      get "/api/v1/teams", params: { tournament_id: 0 }, headers: headers

      expect(response).to have_http_status(:not_found)
    end

    it "404s when there are no tournaments at all" do
      get "/api/v1/teams", headers: headers

      expect(response).to have_http_status(:not_found)
    end

    it "is N+1 free (query count independent of the number of teams)" do
      tournament = create(:tournament, starts_at: 1.day.ago, ends_at: 1.week.from_now)
      teams = create_list(:team, 6, tournament: tournament)
      teams.each_slice(2) { |home, away| create(:match, tournament: tournament, home_team: home, away_team: away) }

      query_count = 0
      counter = lambda do |_name, _started, _finished, _id, payload|
        query_count += 1 unless %w[SCHEMA TRANSACTION].include?(payload[:name])
      end

      ActiveSupport::Notifications.subscribed(counter, "sql.active_record") do
        get "/api/v1/teams", params: { tournament_id: tournament.id }, headers: headers
      end

      expect(query_count).to be <= 3
    end
  end
end
