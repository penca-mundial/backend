# frozen_string_literal: true

FactoryBot.define do
  factory :scoring_rule do
    rule_type { "exact_score" }
    points { 5 }
  end
end
