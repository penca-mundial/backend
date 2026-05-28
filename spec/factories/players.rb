# frozen_string_literal: true

FactoryBot.define do
  factory :player do
    team
    name { Faker::Name.name }
    sequence(:external_id) { |n| "player-#{n}" }
  end
end
