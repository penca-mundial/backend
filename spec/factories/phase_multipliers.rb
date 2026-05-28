# frozen_string_literal: true

FactoryBot.define do
  factory :phase_multiplier do
    phase { "group_stage" }
    multiplier { 1.0 }
  end
end
