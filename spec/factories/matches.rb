# frozen_string_literal: true

FactoryBot.define do
  factory :match do
    tournament
    home_team { association(:team, tournament: tournament) }
    away_team { association(:team, tournament: tournament) }
    kickoff_at { 1.week.from_now }
    phase { "group_stage" }
    sequence(:external_id) { |n| "match-#{n}" }

    trait :live do
      status { "live" }
    end

    trait :finished do
      status { "finished" }
      home_score { 2 }
      away_score { 1 }
    end

    # A knockout match (advancing_team is allowed outside the group stage).
    # Kept as a shorthand alias for the explicit phase traits below.
    trait :knockout do
      phase { "round_of_16" }
    end

    trait :round_of_32 do
      phase { "round_of_32" }
    end

    trait :round_of_16 do
      phase { "round_of_16" }
    end

    trait :quarter_final do
      phase { "quarter_final" }
    end

    trait :semi_final do
      phase { "semi_final" }
    end

    trait :third_place do
      phase { "third_place" }
    end

    trait :final do
      phase { "final" }
    end
  end
end
