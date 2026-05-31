# frozen_string_literal: true

require "rails_helper"

# rubocop:disable RSpec/DescribeClass
RSpec.describe "Api::V1::TeamsController", type: :request do
  # rubocop:enable RSpec/DescribeClass
  let(:headers) { { "User-Agent" => "rspec" } }

  describe "GET /api/v1/teams" do
    it "returns the tournament's teams ordered by name, serialized extended, publicly" do
      tournament = create(:tournament, starts_at: 1.day.ago, ends_at: 1.week.from_now)
      argentina = create(:team, tournament: tournament, name: "Argentina", code3: "ARG",
                                 flag_url: "http://x/arg.png", external_id: "ext-arg")
      create(:team, tournament: tournament, name: "Brazil")

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
      create(:team, tournament: past, name: "OldTeam")
      current_team = create(:team, tournament: current, name: "CurrentTeam")

      get "/api/v1/teams", headers: headers

      expect(response).to have_http_status(:ok)
      expect(response.parsed_body.map { |t| t["id"] }).to eq([ current_team.id ])
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
      create_list(:team, 6, tournament: tournament)

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
