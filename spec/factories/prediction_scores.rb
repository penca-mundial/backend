# frozen_string_literal: true

FactoryBot.define do
  factory :prediction_score do
    prediction
    points_result { 0 }
    points_advance { 0 }
    multiplier { 1.0 }
    computed_at { Time.current }
  end
end
