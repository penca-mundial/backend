# frozen_string_literal: true

require "rails_helper"

# rubocop:disable RSpec/DescribeClass
RSpec.describe "Api::V1::TournamentPredictionsController", type: :request do
  # rubocop:enable RSpec/DescribeClass
  let(:user)       { create(:user) }
  let(:headers)    { { "User-Agent" => "rspec" } }
  let(:tournament) { create(:tournament, starts_at: 1.week.from_now, ends_at: 5.weeks.from_now) }

  # Picks must PARTICIPATE in the fixture (play a match), not just carry the tag.
  def participating_team(in_tournament)
    create(:team, tournament: in_tournament).tap do |team|
      create(:match, tournament: in_tournament, home_team: team, kickoff_at: in_tournament.starts_at + 1.day)
    end
  end

  describe "GET /api/v1/tournament_predictions/me" do
    it "returns 401 when unauthenticated" do
      tournament
      get "/api/v1/tournament_predictions/me", headers: headers
      expect(response).to have_http_status(:unauthorized)
    end

    context "when authenticated" do
      before { login_as(user, scope: :user) }

      it "returns null when the user has no prediction yet" do
        tournament
        get "/api/v1/tournament_predictions/me", headers: headers

        expect(response).to have_http_status(:ok)
        expect(response.parsed_body).to be_nil
      end

      it "returns the user's prediction when it exists" do
        champion = participating_team(tournament)
        create(:tournament_prediction, user: user, tournament: tournament, champion: champion)

        get "/api/v1/tournament_predictions/me", headers: headers

        expect(response).to have_http_status(:ok)
        expect(response.parsed_body["champion_id"]).to eq(champion.id)
      end

      it "embeds the podium teams and the top scorer, keeping the raw ids and lock state" do
        champion = participating_team(tournament)
        runner_up = participating_team(tournament)
        scorer = create(:player, team: champion)
        create(:tournament_prediction, user: user, tournament: tournament,
                                       champion: champion, runner_up: runner_up, top_scorer: scorer)

        get "/api/v1/tournament_predictions/me", headers: headers

        expect(response).to have_http_status(:ok)
        body = response.parsed_body
        expect(body["champion"]).to include("flag_url", "code3",
                                            "name" => champion.name, "id" => champion.id)
        expect(body["runner_up"]).to include("id" => runner_up.id)
        expect(body["top_scorer"]).to include("name" => scorer.name, "id" => scorer.id)
        expect(body["top_scorer"]["team"]).to include("id" => champion.id)
        # Raw FK ids stay for the editor; lock state preserved.
        expect(body).to include("locked", "locked_at",
                                "champion_id" => champion.id, "top_scorer_id" => scorer.id)
      end

      it "does not issue an N+1 to embed the podium teams and top scorer" do
        champion = participating_team(tournament)
        create(:tournament_prediction, user: user, tournament: tournament,
                                       champion: champion, runner_up: participating_team(tournament),
                                       third_place: participating_team(tournament),
                                       fourth_place: participating_team(tournament),
                                       top_scorer: create(:player, team: champion))

        query_count = 0
        counter = lambda do |_n, _s, _f, _id, payload|
          query_count += 1 unless %w[SCHEMA TRANSACTION].include?(payload[:name])
        end
        ActiveSupport::Notifications.subscribed(counter, "sql.active_record") do
          get "/api/v1/tournament_predictions/me", headers: headers
        end

        # Preloaded: the prediction, each podium belongs_to (a constant 4 — Rails
        # preloads per association name), the scorer and its team. Bounded and
        # independent of data size, not one query per embedded record.
        expect(query_count).to be <= 12
      end
    end
  end

  describe "PUT /api/v1/tournament_predictions" do
    before { login_as(user, scope: :user) }

    it "creates the prediction" do
      champion = participating_team(tournament)

      expect do
        put "/api/v1/tournament_predictions", params: { champion_id: champion.id }, headers: headers
      end.to change(TournamentPrediction, :count).by(1)

      expect(response).to have_http_status(:ok)
      expect(response.parsed_body["champion_id"]).to eq(champion.id)
    end

    it "returns 422 once the prediction deadline (first kickoff - 1 minute) has passed" do
      started = create(:tournament, starts_at: 1.day.ago, ends_at: 30.days.from_now)
      create(:match, tournament: started, kickoff_at: 30.seconds.from_now)

      put "/api/v1/tournament_predictions", params: {}, headers: headers

      expect(response).to have_http_status(:unprocessable_content)
    end

    it "binds the prediction to the current tournament (resolver), not the first by id" do
      create(:tournament, starts_at: 1.month.ago, ends_at: 1.week.ago)                  # past, lower id
      current = create(:tournament, starts_at: 1.week.from_now, ends_at: 5.weeks.from_now) # upcoming
      champion = participating_team(current)

      put "/api/v1/tournament_predictions", params: { champion_id: champion.id }, headers: headers

      expect(response).to have_http_status(:ok)
      # If resolution fell back to the first-by-id (past) tournament, the champion
      # would not belong to it and this would 422; success proves it resolved current.
      expect(TournamentPrediction.sole.tournament).to eq(current)
    end
  end
end
