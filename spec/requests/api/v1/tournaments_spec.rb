# frozen_string_literal: true

require "rails_helper"

# rubocop:disable RSpec/DescribeClass
RSpec.describe "Api::V1::TournamentsController", type: :request do
  # rubocop:enable RSpec/DescribeClass
  let(:headers) { { "User-Agent" => "rspec" } }

  describe "GET /api/v1/tournaments/current" do
    it "returns the resolved tournament with its fields and derived values, publicly" do
      tournament = create(:tournament,
                          name: "FIFA World Cup 2026",
                          starts_at: 2.days.from_now, ends_at: 32.days.from_now,
                          external_code: "WC")

      get "/api/v1/tournaments/current", headers: headers

      expect(response).to have_http_status(:ok)
      body = response.parsed_body
      expect(body).to include(
        "id" => tournament.id,
        "name" => "FIFA World Cup 2026",
        "external_code" => "WC",
        "champion_id" => nil, "runner_up_id" => nil, "third_place_id" => nil,
        "fourth_place_id" => nil, "top_scorer_id" => nil,
        "is_locked" => false
      )
      expect(body).to include("starts_at", "ends_at")
      expect(body["seconds_until_kickoff"]).to be > 0
    end

    it "marks an already-started tournament as locked with a zero countdown" do
      create(:tournament, starts_at: 1.day.ago, ends_at: 1.week.from_now)

      get "/api/v1/tournaments/current", headers: headers

      expect(response.parsed_body).to include("is_locked" => true, "seconds_until_kickoff" => 0)
    end

    it "resolves by precedence (an active tournament beats an existing past one), not by id" do
      create(:tournament, starts_at: 1.month.ago, ends_at: 1.week.ago)
      active = create(:tournament, starts_at: 1.day.ago, ends_at: 1.week.from_now)

      get "/api/v1/tournaments/current", headers: headers

      expect(response.parsed_body["id"]).to eq(active.id)
    end

    it "404s when there are no tournaments" do
      get "/api/v1/tournaments/current", headers: headers

      expect(response).to have_http_status(:not_found)
    end

    it "issues a bounded number of queries (no association N+1)" do
      create(:tournament, starts_at: 1.day.ago, ends_at: 1.week.from_now)

      query_count = 0
      counter = lambda do |_name, _started, _finished, _id, payload|
        query_count += 1 unless %w[SCHEMA TRANSACTION].include?(payload[:name])
      end

      ActiveSupport::Notifications.subscribed(counter, "sql.active_record") do
        get "/api/v1/tournaments/current", headers: headers
      end

      # One resolver query (active branch short-circuits); the blueprint reads
      # only columns, so nothing scales with associations.
      expect(query_count).to be <= 2
    end
  end
end
