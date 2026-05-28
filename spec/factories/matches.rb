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
    trait :knockout do
      phase { "round_of_16" }
    end
  end
end
