# frozen_string_literal: true

FactoryBot.define do
  factory :tournament do
    sequence(:name) { |n| "#{Faker::Address.country} World Cup #{2000 + n}" }
    starts_at { Faker::Time.forward(days: 30) }
    ends_at { starts_at + 30.days }
  end
end
