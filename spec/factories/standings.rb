# frozen_string_literal: true

FactoryBot.define do
  factory :standing do
    tournament
    team { association(:team, tournament: tournament) }
    group { "A" }
    position { 1 }
    played_games { 3 }
    won { 2 }
    draw { 1 }
    lost { 0 }
    goals_for { 5 }
    goals_against { 2 }
    goal_difference { 3 }
    points { 7 }
    form { "W,W,D" }
  end
end
