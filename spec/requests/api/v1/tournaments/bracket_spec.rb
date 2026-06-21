# frozen_string_literal: true

require "rails_helper"

# rubocop:disable RSpec/DescribeClass
RSpec.describe "Api::V1::Tournaments::BracketController", type: :request do
  # rubocop:enable RSpec/DescribeClass
  let(:user)       { create(:user) }
  let(:tournament) { create(:tournament) }
  let(:headers)    { { "User-Agent" => "rspec" } }

  # A knockout match in the tournament. Finished + a past kickoff -> the pick is
  # locked; scheduled + a future kickoff -> open (pick must stay hidden).
  def ko_match(phase:, bracket_position:, finished: true)
    if finished
      create(:match, :finished, tournament: tournament, phase: phase, kickoff_at: 1.day.ago,
                                bracket_position: bracket_position)
    else
      create(:match, tournament: tournament, phase: phase, kickoff_at: 1.week.from_now,
                     status: "scheduled", bracket_position: bracket_position)
    end
  end

  # A knockout prediction (the model requires the advancing-team pick): the home
  # team is picked to advance.
  def predict(match)
    create(:prediction, user: user, match: match,
                        predicted_home_score: 1, predicted_away_score: 0,
                        predicted_advancing_team_id: match.home_team_id)
  end

  describe "GET /api/v1/tournaments/:id/bracket" do
    it "returns only knockout matches, ordered by round then bracket_position" do
      create(:match, tournament: tournament, phase: "group_stage", group: "A") # excluded
      qf1 = ko_match(phase: "quarter_final", bracket_position: 1)
      qf0 = ko_match(phase: "quarter_final", bracket_position: 0)
      sf  = ko_match(phase: "semi_final",    bracket_position: 0)

      get "/api/v1/tournaments/#{tournament.id}/bracket", headers: headers

      expect(response).to have_http_status(:ok)
      ids = response.parsed_body["matches"].map { |m| m["id"] }
      expect(ids).to eq([ qf0.id, qf1.id, sf.id ]) # group match absent; bp0 before bp1
    end

    it "exposes the topology fields (bracket view) on each match" do
      ko_match(phase: "quarter_final", bracket_position: 0)

      get "/api/v1/tournaments/#{tournament.id}/bracket", headers: headers

      expect(response.parsed_body["matches"].first).to include(
        "feeds_into_match_id", "feeds_into_slot", "bracket_position"
      )
    end

    context "when anonymous" do
      it "never embeds my_prediction" do
        match = ko_match(phase: "quarter_final", bracket_position: 0)
        predict(match)

        get "/api/v1/tournaments/#{tournament.id}/bracket", headers: headers

        row = response.parsed_body["matches"].first
        expect(row).to have_key("my_prediction")
        expect(row["my_prediction"]).to be_nil
      end
    end

    context "when signed in" do
      before { login_as(user, scope: :user) }

      it "embeds my_prediction (incl. predicted_advancing_team_id) for a locked match" do
        match = ko_match(phase: "quarter_final", bracket_position: 0) # finished -> locked
        predict(match)

        get "/api/v1/tournaments/#{tournament.id}/bracket", headers: headers

        row = response.parsed_body["matches"].find { |m| m["id"] == match.id }
        expect(row["my_prediction"]).to include(
          "predicted_advancing_team_id" => match.home_team_id,
          "predicted_home_score" => 1,
          "locked" => true
        )
      end

      # The hard server-side gate: a future open knockout match must NOT leak the
      # viewer's advancing-team pick to a rival reading the bracket.
      it "never exposes the pick of an open (not-locked) future knockout match" do
        open_match = ko_match(phase: "semi_final", bracket_position: 0, finished: false)
        predict(open_match)

        get "/api/v1/tournaments/#{tournament.id}/bracket", headers: headers

        row = response.parsed_body["matches"].find { |m| m["id"] == open_match.id }
        expect(row["my_prediction"]).to be_nil
        expect(response.body).not_to include("predicted_advancing_team_id")
      end

      it "issues no N+1 across knockout matches (bounded, independent of count)" do
        6.times { |i| predict(ko_match(phase: "quarter_final", bracket_position: i)) }

        query_count = 0
        counter = lambda do |_n, _s, _f, _id, payload|
          query_count += 1 unless %w[SCHEMA TRANSACTION].include?(payload[:name])
        end
        ActiveSupport::Notifications.subscribed(counter, "sql.active_record") do
          get "/api/v1/tournaments/#{tournament.id}/bracket", headers: headers
        end

        # matches + teams + the viewer's predictions/matches/scores load in a
        # bounded number of queries — well under the per-match count (6 matches).
        expect(query_count).to be <= 12
      end
    end
  end
end
