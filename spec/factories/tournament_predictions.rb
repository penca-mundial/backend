# frozen_string_literal: true

FactoryBot.define do
  factory :tournament_prediction do
    user
    tournament

    # A fully filled-in prediction (all five fields point into the tournament's
    # FIXTURE: picks must participate, so the trait also creates the matches).
    trait :complete do
      champion { association(:team, tournament: tournament) }
      runner_up { association(:team, tournament: tournament) }
      third_place { association(:team, tournament: tournament) }
      fourth_place { association(:team, tournament: tournament) }
      top_scorer { association(:player, team: champion) }

      after(:build) do |prediction|
        create(:match, tournament: prediction.tournament,
                       home_team: prediction.champion, away_team: prediction.runner_up)
        create(:match, tournament: prediction.tournament,
                       home_team: prediction.third_place, away_team: prediction.fourth_place)
      end
    end
  end
end
