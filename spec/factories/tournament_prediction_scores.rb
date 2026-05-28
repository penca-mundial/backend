# frozen_string_literal: true

FactoryBot.define do
  factory :tournament_prediction_score do
    tournament_prediction
    points_champion { 0 }
    points_runner_up { 0 }
    points_third { 0 }
    points_fourth { 0 }
    points_top_scorer { 0 }
    computed_at { Time.current }
  end
end
