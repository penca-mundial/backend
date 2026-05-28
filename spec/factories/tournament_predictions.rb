# frozen_string_literal: true

FactoryBot.define do
  factory :tournament_prediction do
    user
    tournament

    # A fully filled-in prediction (all five fields point into the tournament).
    trait :complete do
      champion { association(:team, tournament: tournament) }
      runner_up { association(:team, tournament: tournament) }
      third_place { association(:team, tournament: tournament) }
      fourth_place { association(:team, tournament: tournament) }
      top_scorer { association(:player, team: champion) }
    end
  end
end
