# frozen_string_literal: true

require "rails_helper"

# rubocop:disable RSpec/DescribeClass
RSpec.describe "Api::V1::Tournaments::ProjectedBracketController", type: :request do
  # rubocop:enable RSpec/DescribeClass
  let(:user) { create(:user) }
  # external_code "DEMO" -> db/seeds/data/brackets/demo.yml (first_round
  # quarter_final, 4 slots: two determinate, two with a best-third side).
  let(:tournament) { create(:tournament, external_code: "DEMO") }
  let(:headers) { { "User-Agent" => "rspec" } }

  def build_group(letter, size = 4)
    teams = Array.new(size) { |i| create(:team, tournament: tournament, name: "#{letter}#{i + 1}") }
    teams.combination(2).each do |winner, loser|
      create(:match, tournament: tournament, phase: "group_stage", group: letter, status: "finished",
                     home_team: winner, away_team: loser, home_score: 1, away_score: 0)
    end
    teams
  end

  describe "GET /api/v1/tournaments/:id/bracket/projected" do
    it "requires authentication" do
      get "/api/v1/tournaments/#{tournament.id}/bracket/projected", headers: headers

      expect(response).to have_http_status(:unauthorized)
    end

    context "when signed in" do
      before { login_as(user, scope: :user) }

      it "returns the projected first round: determinate sides resolved, best-third null" do
        a = build_group("A")
        b = build_group("B")

        get "/api/v1/tournaments/#{tournament.id}/bracket/projected", headers: headers

        expect(response).to have_http_status(:ok)
        body = response.parsed_body
        expect(body["projected"]).to be(true)
        expect(body["round_of_32"].size).to eq(4) # demo.yml slots

        slot0 = body["round_of_32"].find { |s| s["bracket_position"] == 0 } # {A,1} vs {B,2}
        expect(slot0["home"]["id"]).to eq(a[0].id)
        expect(slot0["away"]["id"]).to eq(b[1].id)
        expect(slot0["source"]).to eq("projected")

        slot2 = body["round_of_32"].find { |s| s["bracket_position"] == 2 } # {third} vs {B,4}
        expect(slot2["home"]).to be_nil           # best third -> A definir
        expect(slot2["away"]["id"]).to eq(b[3].id) # B 4th
      end

      it "issues no N+1 (bounded, independent of the group/match count)" do
        build_group("A")
        build_group("B")

        query_count = 0
        counter = lambda do |_n, _s, _f, _id, payload|
          query_count += 1 unless %w[SCHEMA TRANSACTION].include?(payload[:name])
        end
        ActiveSupport::Notifications.subscribed(counter, "sql.active_record") do
          get "/api/v1/tournaments/#{tournament.id}/bracket/projected", headers: headers
        end

        expect(query_count).to be <= 12
      end
    end
  end
end
