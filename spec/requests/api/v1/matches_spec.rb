# frozen_string_literal: true

require "rails_helper"

# rubocop:disable RSpec/DescribeClass
RSpec.describe "Api::V1::MatchesController", type: :request do
  # rubocop:enable RSpec/DescribeClass
  let(:user)    { create(:user) }
  let(:headers) { { "User-Agent" => "rspec" } }

  describe "GET /api/v1/matches" do
    it "filters by status" do
      finished = create(:match, :finished, kickoff_at: 2.days.ago)
      create(:match, kickoff_at: 1.week.from_now) # scheduled

      get "/api/v1/matches", params: { status: "finished" }, headers: headers

      expect(response).to have_http_status(:ok)
      ids = response.parsed_body.map { |m| m["id"] }
      expect(ids).to eq([ finished.id ])
    end

    it "filters by team (either side)" do
      target = create(:match, kickoff_at: 1.week.from_now)
      create(:match, kickoff_at: 1.week.from_now)

      get "/api/v1/matches", params: { team_id: target.home_team_id }, headers: headers

      ids = response.parsed_body.map { |m| m["id"] }
      expect(ids).to eq([ target.id ])
    end
  end

  describe "GET /api/v1/matches/:id" do
    let(:fixture) { create(:match, kickoff_at: 1.week.from_now) }

    it "exposes the group field" do
      grouped = create(:match, kickoff_at: 1.week.from_now, group: "C")

      get "/api/v1/matches/#{grouped.id}", headers: headers

      expect(response).to have_http_status(:ok)
      expect(response.parsed_body).to include("group" => "C")
    end

    it "embeds my_prediction when authenticated" do
      create(:prediction, user: user, match: fixture, predicted_home_score: 2, predicted_away_score: 1)
      login_as(user, scope: :user)

      get "/api/v1/matches/#{fixture.id}", headers: headers

      expect(response).to have_http_status(:ok)
      expect(response.parsed_body["my_prediction"]).to include("predicted_home_score" => 2)
      expect(response.parsed_body["home_team"]).to include("id" => fixture.home_team_id)
    end

    it "omits my_prediction when not authenticated" do
      get "/api/v1/matches/#{fixture.id}", headers: headers

      expect(response).to have_http_status(:ok)
      expect(response.parsed_body).not_to have_key("my_prediction")
    end

    it "caches the public match payload via Rails.cache" do
      allow(Rails.cache).to receive(:fetch).and_call_original

      get "/api/v1/matches/#{fixture.id}", headers: headers

      expect(Rails.cache).to have_received(:fetch)
        .with(a_string_including("match:#{fixture.id}"), hash_including(:expires_in))
    end
  end

  describe "GET /api/v1/matches/live" do
    it "returns only live matches" do
      live = create(:match, :live, kickoff_at: 1.hour.ago)
      create(:match, kickoff_at: 1.week.from_now)

      get "/api/v1/matches/live", headers: headers

      ids = response.parsed_body.map { |m| m["id"] }
      expect(ids).to eq([ live.id ])
    end
  end

  describe "GET /api/v1/matches/today" do
    it "returns matches in the requested timezone's day window" do
      zone = ActiveSupport::TimeZone["America/Montevideo"]
      today = create(:match, kickoff_at: zone.now.change(hour: 12))
      create(:match, kickoff_at: 10.days.from_now)

      get "/api/v1/matches/today", params: { tz: "America/Montevideo" }, headers: headers

      ids = response.parsed_body.map { |m| m["id"] }
      expect(ids).to include(today.id)
      expect(ids.size).to eq(1)
    end
  end
end
