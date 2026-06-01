# frozen_string_literal: true

require "rails_helper"

# rubocop:disable RSpec/DescribeClass
RSpec.describe "Api::V1::PredictionsController", type: :request do
  # rubocop:enable RSpec/DescribeClass
  let(:user)     { create(:user) }
  let(:headers)  { { "User-Agent" => "rspec" } }
  let(:upcoming) { create(:match, kickoff_at: 1.week.from_now) } # group_stage, scheduled

  describe "GET /api/v1/predictions/me" do
    it "returns 401 when unauthenticated" do
      get "/api/v1/predictions/me", headers: headers
      expect(response).to have_http_status(:unauthorized)
    end

    context "when authenticated" do
      before { login_as(user, scope: :user) }

      it "returns only the authenticated user's predictions, with a total-count header" do
        create(:prediction, user: user, match: upcoming)
        create(:prediction, user: create(:user), match: upcoming) # someone else's

        get "/api/v1/predictions/me", headers: headers

        expect(response).to have_http_status(:ok)
        expect(response.parsed_body.size).to eq(1)
        expect(response.parsed_body.first["match_id"]).to eq(upcoming.id)
        expect(response.headers["X-Total-Count"]).to eq("1")
      end

      it "filters by match_id" do
        create(:prediction, user: user, match: upcoming)
        create(:prediction, user: user, match: create(:match, kickoff_at: 1.week.from_now))

        get "/api/v1/predictions/me", params: { match_id: upcoming.id }, headers: headers

        expect(response.parsed_body.size).to eq(1)
        expect(response.parsed_body.first["match_id"]).to eq(upcoming.id)
      end

      it "includes points_earned: 0 for every prediction when none are scored yet" do
        create(:prediction, user: user, match: upcoming)
        create(:prediction, user: user, match: create(:match, kickoff_at: 1.week.from_now))

        get "/api/v1/predictions/me", headers: headers

        expect(response).to have_http_status(:ok)
        expect(response.parsed_body.map { |p| p["points_earned"] }).to all(eq(0))
      end

      it "exposes points_earned from the prediction's score once computed" do
        prediction = create(:prediction, user: user, match: upcoming)
        # total_points = (points_result + points_advance) * multiplier => (5 + 1) * 1.0 = 6
        create(:prediction_score, prediction: prediction, points_result: 5, points_advance: 1, multiplier: 1.0)

        get "/api/v1/predictions/me", headers: headers

        expect(response.parsed_body.first["points_earned"]).to eq(6)
      end

      it "does not N+1 on points_earned across predictions" do
        3.times { create(:prediction, user: user, match: create(:match, kickoff_at: 1.week.from_now)) }

        query_count = 0
        counter = lambda do |_name, _started, _finished, _id, payload|
          query_count += 1 unless %w[SCHEMA TRANSACTION].include?(payload[:name])
        end

        ActiveSupport::Notifications.subscribed(counter, "sql.active_record") do
          get "/api/v1/predictions/me", headers: headers
        end

        expect(query_count).to be <= 6
      end
    end
  end

  describe "PUT /api/v1/predictions" do
    before { login_as(user, scope: :user) }

    def put_prediction(params)
      put "/api/v1/predictions", params: params, headers: headers
    end

    it "creates a new prediction" do
      expect do
        put_prediction(match_id: upcoming.id, predicted_home_score: 2, predicted_away_score: 1)
      end.to change(Prediction, :count).by(1)

      expect(response).to have_http_status(:ok)
      expect(response.parsed_body).to include("match_id" => upcoming.id, "predicted_home_score" => 2)
    end

    it "updates an existing prediction instead of creating a second" do
      create(:prediction, user: user, match: upcoming, predicted_home_score: 0, predicted_away_score: 0)

      expect do
        put_prediction(match_id: upcoming.id, predicted_home_score: 3, predicted_away_score: 0)
      end.not_to change(Prediction, :count)

      expect(response).to have_http_status(:ok)
      expect(response.parsed_body["predicted_home_score"]).to eq(3)
    end

    it "returns 422 when the match is locked" do
      locked = create(:match, kickoff_at: 30.seconds.from_now)

      put_prediction(match_id: locked.id, predicted_home_score: 1, predicted_away_score: 0)

      expect(response).to have_http_status(:unprocessable_content)
    end

    it "returns 422 when scores are out of range" do
      put_prediction(match_id: upcoming.id, predicted_home_score: 99, predicted_away_score: 0)

      expect(response).to have_http_status(:unprocessable_content)
    end

    it "returns 422 for a knockout match without an advancing team" do
      knockout = create(:match, :round_of_16, kickoff_at: 1.week.from_now)

      put_prediction(match_id: knockout.id, predicted_home_score: 1, predicted_away_score: 1)

      expect(response).to have_http_status(:unprocessable_content)
    end
  end

  describe "DELETE /api/v1/predictions/:id" do
    before { login_as(user, scope: :user) }

    it "deletes an own, still-open prediction (204)" do
      prediction = create(:prediction, user: user, match: upcoming)

      expect do
        delete "/api/v1/predictions/#{prediction.id}", headers: headers
      end.to change(Prediction, :count).by(-1)

      expect(response).to have_http_status(:no_content)
    end

    it "returns 403 for another user's prediction" do
      others = create(:prediction, user: create(:user), match: upcoming)

      delete "/api/v1/predictions/#{others.id}", headers: headers

      expect(response).to have_http_status(:forbidden)
      expect(others.reload).to be_present
    end

    it "returns 422 when the match is already locked" do
      locked_match = create(:match, kickoff_at: 30.seconds.from_now)
      prediction = create(:prediction, user: user, match: locked_match)

      delete "/api/v1/predictions/#{prediction.id}", headers: headers

      expect(response).to have_http_status(:unprocessable_content)
      expect(prediction.reload).to be_present
    end
  end
end
