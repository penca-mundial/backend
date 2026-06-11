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

    it "exposes the live minute field" do
      in_play = create(:match, :live, kickoff_at: 1.hour.ago, minute: 67)

      get "/api/v1/matches/#{in_play.id}", headers: headers

      expect(response).to have_http_status(:ok)
      expect(response.parsed_body).to include("minute" => 67)
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

    context "when authenticated" do
      before do
        create(:scoring_rule, rule_type: "exact_score", points: 5)
        login_as(user, scope: :user)
      end

      it "embeds my_prediction and projected_points at the current live score" do
        live = create(:match, :live, kickoff_at: 1.hour.ago, home_score: 2, away_score: 1)
        create(:prediction, user: user, match: live, predicted_home_score: 2, predicted_away_score: 1)

        get "/api/v1/matches/live", headers: headers

        expect(response).to have_http_status(:ok)
        row = response.parsed_body.first
        expect(row["my_prediction"]).to include("predicted_home_score" => 2, "predicted_away_score" => 1)
        expect(row["projected_points"]).to eq(5) # exact match of the live score
      end

      it "nulls my_prediction and projected_points without a prediction" do
        create(:match, :live, kickoff_at: 1.hour.ago, home_score: 0, away_score: 0)

        get "/api/v1/matches/live", headers: headers

        row = response.parsed_body.first
        expect(row).to have_key("my_prediction")
        expect(row["my_prediction"]).to be_nil
        expect(row["projected_points"]).to be_nil
      end

      it "does not issue an N+1 across live matches" do
        3.times do |i|
          m = create(:match, :live, kickoff_at: (i + 1).hours.ago, home_score: 1, away_score: 0)
          create(:prediction, user: user, match: m, predicted_home_score: 1, predicted_away_score: 0)
        end

        query_count = 0
        counter = lambda do |_n, _s, _f, _id, payload|
          query_count += 1 unless %w[SCHEMA TRANSACTION].include?(payload[:name])
        end
        ActiveSupport::Notifications.subscribed(counter, "sql.active_record") do
          get "/api/v1/matches/live", headers: headers
        end

        # Predictions + scores batch-loaded, scoring config memoized across
        # matches: bounded and independent of the live-match count.
        expect(query_count).to be <= 10
      end
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

  describe "GET /api/v1/matches/next" do
    it "returns the soonest scheduled match still ahead of now, with its teams" do
      soonest = create(:match, kickoff_at: 2.hours.from_now)
      create(:match, kickoff_at: 3.days.from_now)       # later scheduled
      create(:match, :finished, kickoff_at: 1.hour.from_now) # sooner but finished

      get "/api/v1/matches/next", headers: headers

      expect(response).to have_http_status(:ok)
      expect(response.parsed_body).to include("id" => soonest.id)
      expect(response.parsed_body["home_team"]).to include("flag_url", "id" => soonest.home_team_id)
    end

    it "ignores past kickoffs" do
      create(:match, :finished, kickoff_at: 2.days.ago)
      upcoming = create(:match, kickoff_at: 5.days.from_now)

      get "/api/v1/matches/next", headers: headers

      expect(response.parsed_body).to include("id" => upcoming.id)
    end

    it "returns null when no scheduled match is upcoming" do
      create(:match, :finished, kickoff_at: 2.days.ago)

      get "/api/v1/matches/next", headers: headers

      expect(response).to have_http_status(:ok)
      expect(response.parsed_body).to be_nil
    end
  end

  describe "GET /api/v1/matches/last_finished" do
    it "returns the most recently kicked-off finished match, with teams and scores" do
      create(:match, :finished, kickoff_at: 5.days.ago)
      latest = create(:match, :finished, kickoff_at: 1.day.ago, home_score: 3, away_score: 2)
      create(:match, kickoff_at: 1.day.from_now) # scheduled, ignored

      get "/api/v1/matches/last_finished", headers: headers

      expect(response).to have_http_status(:ok)
      expect(response.parsed_body).to include("id" => latest.id, "home_score" => 3, "away_score" => 2)
      expect(response.parsed_body["away_team"]).to include("id" => latest.away_team_id)
    end

    it "embeds my_prediction when authenticated" do
      latest = create(:match, :finished, kickoff_at: 1.day.ago)
      create(:prediction, user: user, match: latest, predicted_home_score: 1, predicted_away_score: 0)
      login_as(user, scope: :user)

      get "/api/v1/matches/last_finished", headers: headers

      expect(response).to have_http_status(:ok)
      expect(response.parsed_body["my_prediction"]).to include(
        "predicted_home_score" => 1, "predicted_away_score" => 0
      )
    end

    it "omits my_prediction when not authenticated" do
      create(:match, :finished, kickoff_at: 1.day.ago)

      get "/api/v1/matches/last_finished", headers: headers

      expect(response).to have_http_status(:ok)
      expect(response.parsed_body).not_to have_key("my_prediction")
    end

    it "returns null when nothing is finished" do
      create(:match, kickoff_at: 1.day.from_now)

      get "/api/v1/matches/last_finished", headers: headers

      expect(response).to have_http_status(:ok)
      expect(response.parsed_body).to be_nil
    end
  end
end
