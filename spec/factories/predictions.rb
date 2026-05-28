# frozen_string_literal: true

FactoryBot.define do
  factory :prediction do
    user
    match
    predicted_home_score { rand(0..5) }
    predicted_away_score { rand(0..5) }

    # A prediction for a knockout match must name the team that advances.
    trait :knockout do
      association :match, factory: %i[match knockout], strategy: :create
      predicted_advancing_team { match.home_team }
    end
  end
end
