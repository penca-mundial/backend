# frozen_string_literal: true

require "rails_helper"

# rubocop:disable RSpec/DescribeClass
RSpec.describe "Api::V1::TournamentPredictionsController", type: :request do
  # rubocop:enable RSpec/DescribeClass
  let(:user)       { create(:user) }
  let(:headers)    { { "User-Agent" => "rspec" } }
  let(:tournament) { create(:tournament, starts_at: 1.week.from_now, ends_at: 5.weeks.from_now) }

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
        champion = create(:team, tournament: tournament)
        create(:tournament_prediction, user: user, tournament: tournament, champion: champion)

        get "/api/v1/tournament_predictions/me", headers: headers

        expect(response).to have_http_status(:ok)
        expect(response.parsed_body["champion_id"]).to eq(champion.id)
      end
    end
  end

  describe "PUT /api/v1/tournament_predictions" do
    before { login_as(user, scope: :user) }

    it "creates the prediction" do
      champion = create(:team, tournament: tournament)

      expect do
        put "/api/v1/tournament_predictions", params: { champion_id: champion.id }, headers: headers
      end.to change(TournamentPrediction, :count).by(1)

      expect(response).to have_http_status(:ok)
      expect(response.parsed_body["champion_id"]).to eq(champion.id)
    end

    it "returns 422 once the tournament has started" do
      create(:tournament, starts_at: 1.day.ago, ends_at: 30.days.from_now)

      put "/api/v1/tournament_predictions", params: {}, headers: headers

      expect(response).to have_http_status(:unprocessable_content)
    end
  end
end
