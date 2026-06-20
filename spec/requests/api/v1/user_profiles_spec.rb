# frozen_string_literal: true

require "rails_helper"

# rubocop:disable RSpec/DescribeClass
RSpec.describe "Api::V1::UserProfilesController", type: :request do
  # rubocop:enable RSpec/DescribeClass
  let(:viewer)  { create(:user) }
  let(:target)  { create(:user, username: "target_user") }
  let(:headers) { { "User-Agent" => "rspec" } }

  # A single tournament so CurrentTournamentQuery resolves to it. starts_at is in
  # the past so it is unambiguously "the current one"; lock state is driven by
  # match kickoffs (see Tournament#predictions_lock_at), not these dates.
  let(:tournament) { create(:tournament, starts_at: 10.days.ago, ends_at: 30.days.from_now) }

  before do
    create(:scoring_rule, rule_type: "exact_score", points: 5)
    create(:scoring_rule, rule_type: "correct_winner", points: 2)
    create(:scoring_rule, rule_type: "correct_goal_difference", points: 3)
    create(:phase_multiplier, phase: "group_stage", multiplier: 1.0)
  end

  # A finished match in the tournament with the given final score.
  def finished_match(home:, away:, kickoff: 2.days.ago)
    create(:match, :finished, tournament: tournament, home_score: home, away_score: away, kickoff_at: kickoff)
  end

  # Give the user a prediction for a finished match plus the stored score row that
  # the stats aggregate over (breakdown carries the rule the leaderboard reads).
  def score(user, match, rule:, home:, away:)
    prediction = create(:prediction, user: user, match: match,
                                     predicted_home_score: home, predicted_away_score: away)
    create(:prediction_score, prediction: prediction, points_result: 5, multiplier: 1.0,
                              breakdown: { "result_rule" => rule })
    prediction
  end

  describe "GET /api/v1/users/:id/profile" do
    it "requires authentication" do
      get "/api/v1/users/#{target.id}/profile", headers: headers

      expect(response).to have_http_status(:unauthorized)
    end

    context "when signed in" do
      before { login_as(viewer, scope: :user) }

      it "404s for the service account" do
        system_user = create(:user, :system)

        get "/api/v1/users/#{system_user.id}/profile", headers: headers

        expect(response).to have_http_status(:not_found)
      end

      it "404s for an unknown user" do
        get "/api/v1/users/0/profile", headers: headers

        expect(response).to have_http_status(:not_found)
      end

      it "returns the target's identity and global ranking" do
        tournament
        score(target, finished_match(home: 2, away: 1), rule: "exact_score", home: 2, away: 1)

        get "/api/v1/users/#{target.id}/profile", headers: headers

        expect(response).to have_http_status(:ok)
        body = response.parsed_body
        expect(body["user"]).to include("id" => target.id, "username" => "target_user")
        expect(body["global_ranking"]).to include("rank_position", "points", "total")
        expect(body["global_ranking"]["points"]).to eq(5)
      end

      it "buckets scored predictions by result_rule and excludes live matches (stats)" do
        tournament
        score(target, finished_match(home: 2, away: 1), rule: "exact_score", home: 2, away: 1)
        score(target, finished_match(home: 1, away: 0), rule: "correct_winner", home: 3, away: 0)
        score(target, finished_match(home: 2, away: 0), rule: "correct_goal_difference", home: 3, away: 1)
        score(target, finished_match(home: 0, away: 1), rule: "no_match", home: 4, away: 4)

        # A live match the target predicted: NO PredictionScore row exists yet,
        # so it must not appear in any stat bucket.
        live = create(:match, :live, tournament: tournament, home_score: 1, away_score: 0)
        create(:prediction, user: target, match: live, predicted_home_score: 1, predicted_away_score: 0)

        get "/api/v1/users/#{target.id}/profile", headers: headers

        expect(response.parsed_body["stats"]).to eq(
          "exact" => 1, "correct_winner" => 1, "goal_difference" => 1, "missed" => 1, "total" => 4
        )
      end

      it "lists shared groups (general + shared private), never non-shared ones" do
        general = create(:group, :general_pool, owner: create(:user), name: "Pool General")
        shared  = create(:group, owner: create(:user), name: "Los Amigos")
        private_to_target = create(:group, owner: create(:user), name: "Solo Target")

        [ general, shared ].each do |g|
          create(:group_membership, group: g, user: viewer)
          create(:group_membership, group: g, user: target)
        end
        create(:group_membership, group: private_to_target, user: target)

        tournament

        get "/api/v1/users/#{target.id}/profile", headers: headers

        names = response.parsed_body["shared_groups"].map { |entry| entry["group"]["name"] }
        expect(names).to contain_exactly("Pool General", "Los Amigos")
        expect(response.parsed_body["shared_groups"].first["group"]["is_general_pool"]).to be(true)
      end

      it "hides the tournament prediction before the tournament starts" do
        # All matches in the future -> predictions not locked yet.
        create(:match, tournament: tournament, kickoff_at: 5.days.from_now)

        get "/api/v1/users/#{target.id}/profile", headers: headers

        expect(response.parsed_body["tournament_prediction"]).to eq(
          "available" => false, "reason" => "tournament_not_started"
        )
      end

      it "reveals the tournament prediction once the tournament has started" do
        match = finished_match(home: 1, away: 0) # a past kickoff -> locked
        champion = match.home_team # a participating team (pickable)
        create(:tournament_prediction, user: target, tournament: tournament, champion: champion)

        get "/api/v1/users/#{target.id}/profile", headers: headers

        tp = response.parsed_body["tournament_prediction"]
        expect(tp["available"]).to be(true)
        expect(tp["prediction"]["champion_id"]).to eq(champion.id)
      end
    end
  end

  describe "GET /api/v1/users/:id/predictions" do
    before { login_as(viewer, scope: :user) }

    it "requires authentication" do
      logout(:user)

      get "/api/v1/users/#{target.id}/predictions", headers: headers

      expect(response).to have_http_status(:unauthorized)
    end

    # The non-negotiable fairness gate.
    it "never exposes a prediction for a still-open future match" do
      finished = finished_match(home: 2, away: 1)
      create(:prediction, user: target, match: finished, predicted_home_score: 2, predicted_away_score: 1)

      open_future = create(:match, tournament: tournament, kickoff_at: 1.week.from_now)
      create(:prediction, user: target, match: open_future, predicted_home_score: 9, predicted_away_score: 9)

      get "/api/v1/users/#{target.id}/predictions", headers: headers

      ids = response.parsed_body["entries"].map { |entry| entry["id"] }
      expect(ids).to include(finished.id)
      expect(ids).not_to include(open_future.id)
    end

    it "embeds the target's pick and the points it scores" do
      match = finished_match(home: 2, away: 1)
      create(:prediction, user: target, match: match, predicted_home_score: 2, predicted_away_score: 1)

      get "/api/v1/users/#{target.id}/predictions", headers: headers

      entry = response.parsed_body["entries"].find { |e| e["id"] == match.id }
      expect(entry["prediction"]).to include(
        "predicted_home_score" => 2, "predicted_away_score" => 1, "points" => 5
      )
      expect(entry).not_to have_key("my_prediction")
    end

    it "always places the live match on page one, then finished by kickoff desc" do
      recent_finished = finished_match(home: 1, away: 0, kickoff: 1.day.ago)
      live = create(:match, :live, tournament: tournament, home_score: 0, away_score: 0,
                                   kickoff_at: 3.days.ago)
      [ recent_finished, live ].each do |m|
        create(:prediction, user: target, match: m, predicted_home_score: 0, predicted_away_score: 0)
      end

      get "/api/v1/users/#{target.id}/predictions", headers: headers

      ids = response.parsed_body["entries"].map { |entry| entry["id"] }
      expect(ids.first).to eq(live.id) # live first despite its older kickoff
    end

    it "paginates with page / per_page and reports has_more" do
      3.times do |i|
        match = finished_match(home: 1, away: 0, kickoff: (i + 1).days.ago)
        create(:prediction, user: target, match: match, predicted_home_score: 1, predicted_away_score: 0)
      end

      get "/api/v1/users/#{target.id}/predictions?per_page=2&page=1", headers: headers
      first_page = response.parsed_body
      expect(first_page["entries"].size).to eq(2)
      expect(first_page["has_more"]).to be(true)

      get "/api/v1/users/#{target.id}/predictions?per_page=2&page=2", headers: headers
      second_page = response.parsed_body
      expect(second_page["entries"].size).to eq(1)
      expect(second_page["has_more"]).to be(false)
    end

    it "issues no N+1 — query count is independent of the match count" do
      # Warm up prepared statements / connection so the comparison is
      # apples-to-apples (the first request of the example carries one-time cost).
      get "/api/v1/users/#{target.id}/predictions", headers: headers

      counts = [ 2, 8 ].map do |n|
        target.predictions.delete_all
        n.times do |i|
          match = finished_match(home: 1, away: 0, kickoff: (i + 1).days.ago)
          create(:prediction, user: target, match: match, predicted_home_score: 1, predicted_away_score: 0)
        end

        count_queries { get "/api/v1/users/#{target.id}/predictions", headers: headers }
      end

      expect(counts.first).to eq(counts.last)
    end

    def count_queries
      count = 0
      counter = lambda do |_n, _s, _f, _id, payload|
        count += 1 unless %w[SCHEMA TRANSACTION].include?(payload[:name])
      end
      ActiveSupport::Notifications.subscribed(counter, "sql.active_record") { yield }
      count
    end
  end
end
