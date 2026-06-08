# frozen_string_literal: true

require "rails_helper"

RSpec.describe ScoringConfigQuery do
  it "returns the rules and multipliers in canonical enum order, not insertion order" do
    # Insert out of order to prove the query reorders by the enum, not by id.
    create(:scoring_rule, rule_type: "champion_correct", points: 50)
    create(:scoring_rule, rule_type: "exact_score", points: 10)
    create(:scoring_rule, rule_type: "correct_winner", points: 3)
    create(:phase_multiplier, phase: "final", multiplier: 4.0)
    create(:phase_multiplier, phase: "group_stage", multiplier: 1.0)

    config = described_class.call

    expect(config.scoring_rules.map(&:rule_type)).to eq(%w[exact_score correct_winner champion_correct])
    expect(config.phase_multipliers.map(&:phase)).to eq(%w[group_stage final])
  end

  it "includes the special (champion/runner-up/.../top-scorer) rules" do
    %w[champion_correct runner_up_correct third_place_correct fourth_place_correct top_scorer_correct]
      .each { |rule_type| create(:scoring_rule, rule_type: rule_type, points: 1) }

    rule_types = described_class.call.scoring_rules.map(&:rule_type)

    expect(rule_types).to include(
      "champion_correct", "runner_up_correct", "third_place_correct",
      "fourth_place_correct", "top_scorer_correct"
    )
  end

  it "skips enum values that have no row" do
    create(:scoring_rule, rule_type: "exact_score", points: 10)

    config = described_class.call

    expect(config.scoring_rules.map(&:rule_type)).to eq(%w[exact_score])
    expect(config.phase_multipliers).to be_empty
  end

  it "reads each table with a single query" do
    create(:scoring_rule, rule_type: "exact_score", points: 10)
    create(:phase_multiplier, phase: "group_stage", multiplier: 1.0)

    queries = []
    counter = lambda do |_name, _start, _finish, _id, payload|
      sql = payload[:sql]
      queries << sql if sql.include?('FROM "scoring_rules"') || sql.include?('FROM "phase_multipliers"')
    end

    ActiveSupport::Notifications.subscribed(counter, "sql.active_record") do
      config = described_class.call
      config.scoring_rules.map(&:rule_type) # force enumeration
      config.phase_multipliers.map(&:phase)
    end

    expect(queries.size).to eq(2)
  end
end
