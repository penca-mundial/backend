# frozen_string_literal: true

require "rails_helper"

# rubocop:disable RSpec/DescribeClass
RSpec.describe "GET /api/v1/tournaments/:id/standings/projected", type: :request do
  # rubocop:enable RSpec/DescribeClass
  let(:headers)    { { "User-Agent" => "rspec" } }
  let(:tournament) { create(:tournament) }
  let(:user)       { create(:user) }

  def team(name)
    create(:team, tournament: tournament, name: name)
  end

  it "returns 401 when unauthenticated" do
    get "/api/v1/tournaments/#{tournament.id}/standings/projected", headers: headers

    expect(response).to have_http_status(:unauthorized)
  end

  context "when authenticated" do
    before { login_as(user, scope: :user) }

    it "returns the official shape with the user's predictions blended in" do
      alpha = team("Alpha")
      beta  = team("Beta")
      gamma = team("Gamma")
      create(:match, tournament: tournament, phase: "group_stage", group: "A",
                     home_team: alpha, away_team: beta,
                     status: "finished", home_score: 1, away_score: 0)
      scheduled = create(:match, tournament: tournament, phase: "group_stage", group: "A",
                                 home_team: beta, away_team: gamma,
                                 status: "scheduled", home_score: 0, away_score: 0)
      create(:prediction, user: user, match: scheduled,
                          predicted_home_score: 2, predicted_away_score: 0)

      get "/api/v1/tournaments/#{tournament.id}/standings/projected", headers: headers

      expect(response).to have_http_status(:ok)
      groups = response.parsed_body
      expect(groups.size).to eq(1)
      expect(groups.first["name"]).to eq("A")

      rows = groups.first["standings"]
      expect(rows.first.keys).to contain_exactly(
        "team", "played", "won", "drawn", "lost",
        "goals_for", "goals_against", "goal_difference", "points", "position"
      )
      # Realistic data (ADR 0004): ids come through as numbers, not strings.
      expect(rows.first["team"]["id"]).to be_a(Integer)
      expect(rows.first["team"].keys).to contain_exactly("id", "name", "code3", "flag_url")

      beta_row = rows.find { |row| row.dig("team", "id") == beta.id }
      # Official loss (played 1) + predicted win (points only) = hybrid row.
      expect(beta_row).to include(
        "played" => 1, "won" => 0, "lost" => 1,
        "points" => 3, "goals_for" => 2, "goals_against" => 1, "goal_difference" => 1
      )
      # Blended ranking: Beta (3 pts, +1) over Alpha (3 pts, +1... Alpha 1-0 => +1, GF 1).
      # Beta wins the GF tiebreak (2 vs 1).
      expect(rows.map { |row| row.dig("team", "id") }).to eq([ beta.id, alpha.id, gamma.id ])
    end

    it "does not leak another user's projection" do
      home = team("Home")
      away = team("Away")
      scheduled = create(:match, tournament: tournament, phase: "group_stage", group: "B",
                                 home_team: home, away_team: away,
                                 status: "scheduled", home_score: 0, away_score: 0)
      create(:prediction, user: create(:user), match: scheduled,
                          predicted_home_score: 9, predicted_away_score: 0)

      get "/api/v1/tournaments/#{tournament.id}/standings/projected", headers: headers

      rows = response.parsed_body.first["standings"]
      expect(rows).to all(include("points" => 0, "goals_for" => 0))
    end

    it "returns 404 for an unknown tournament" do
      get "/api/v1/tournaments/0/standings/projected", headers: headers

      expect(response).to have_http_status(:not_found)
    end
  end
end
