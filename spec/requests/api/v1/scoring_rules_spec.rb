# frozen_string_literal: true

require "rails_helper"

# rubocop:disable RSpec/DescribeClass
RSpec.describe "GET /api/v1/scoring_rules", type: :request do
  # rubocop:enable RSpec/DescribeClass
  include ActiveSupport::Testing::TimeHelpers

  let(:headers) { { "User-Agent" => "rspec" } }

  it "is public (no authentication required)" do
    create(:scoring_rule, rule_type: "exact_score", points: 10)

    get "/api/v1/scoring_rules", headers: headers

    expect(response).to have_http_status(:ok)
  end

  it "returns the match and special rule points plus phase multipliers from the real models" do
    create(:scoring_rule, rule_type: "exact_score", points: 10)
    create(:scoring_rule, rule_type: "champion_correct", points: 50)
    create(:scoring_rule, rule_type: "top_scorer_correct", points: 25)
    create(:phase_multiplier, phase: "group_stage", multiplier: 1.0)
    create(:phase_multiplier, phase: "final", multiplier: 4.0)

    get "/api/v1/scoring_rules", headers: headers

    body = response.parsed_body
    expect(body.keys).to contain_exactly("scoring_rules", "phase_multipliers")

    rule = body["scoring_rules"].find { |r| r["rule_type"] == "champion_correct" }
    expect(rule).to eq("rule_type" => "champion_correct", "points" => 50, "label" => "Campeón acertado")

    multiplier = body["phase_multipliers"].find { |m| m["phase"] == "final" }
    expect(multiplier).to eq("phase" => "final", "multiplier" => 4.0, "label" => "Final")

    # The special rules are covered, not just the per-match ones.
    expect(body["scoring_rules"].map { |r| r["rule_type"] })
      .to include("exact_score", "champion_correct", "top_scorer_correct")
  end

  it "reflects an admin-edited value rather than a hardcoded constant" do
    create(:scoring_rule, rule_type: "exact_score", points: 99) # non-default

    get "/api/v1/scoring_rules", headers: headers

    points = response.parsed_body["scoring_rules"].first["points"]
    expect(points).to eq(99)
  end

  describe "caching (short TTL dedupes the SPA polling)" do
    # The test env uses a null_store, so swap in a real store to exercise the TTL.
    let(:cache) { ActiveSupport::Cache::MemoryStore.new }

    before { allow(Rails).to receive(:cache).and_return(cache) }

    it "serves a cached body within the TTL and recomputes after it expires" do
      allow(ScoringConfigQuery).to receive(:call).and_call_original

      get "/api/v1/scoring_rules", headers: headers
      get "/api/v1/scoring_rules", headers: headers
      expect(ScoringConfigQuery).to have_received(:call).once # second request is a cache hit

      travel(Api::V1::ScoringRulesController::CACHE_TTL + 1.second) do
        get "/api/v1/scoring_rules", headers: headers
      end
      expect(ScoringConfigQuery).to have_received(:call).twice # recomputed after the TTL
    end
  end
end
