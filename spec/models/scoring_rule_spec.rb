# frozen_string_literal: true

require "rails_helper"

RSpec.describe ScoringRule, type: :model do
  it "has a valid factory" do
    expect(build(:scoring_rule)).to be_valid
  end

  describe "rule_type enum" do
    it "exposes the full closed set of rule types" do
      expect(described_class.rule_types.keys).to match_array(ScoringRule::RULE_TYPES)
    end

    it "rejects a value outside the closed set" do
      expect { build(:scoring_rule, rule_type: "nonsense") }.to raise_error(ArgumentError)
    end
  end

  describe "validations" do
    it "rejects negative points" do
      expect(build(:scoring_rule, points: -1)).not_to be_valid
    end

    it "rejects a duplicate rule_type" do
      create(:scoring_rule, rule_type: "exact_score")

      expect(build(:scoring_rule, rule_type: "exact_score")).not_to be_valid
    end
  end

  describe ".for" do
    it "returns the configured points for a rule type" do
      create(:scoring_rule, rule_type: "exact_score", points: 7)

      expect(described_class.for(:exact_score)).to eq(7)
    end

    it "returns nil for an unconfigured rule type" do
      expect(described_class.for(:correct_winner)).to be_nil
    end
  end
end
