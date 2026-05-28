# frozen_string_literal: true

FactoryBot.define do
  factory :team do
    tournament
    name { Faker::Address.country }
    # Unique 3-letter code (AAA, AAB, AAC, ...).
    sequence(:code3) do |n|
      letters = ("A".."Z").to_a
      [ letters[n / 676 % 26], letters[n / 26 % 26], letters[n % 26] ].join
    end
    sequence(:external_id) { |n| "team-#{n}" }
  end
end
