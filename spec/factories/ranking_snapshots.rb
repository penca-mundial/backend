# frozen_string_literal: true

FactoryBot.define do
  factory :ranking_snapshot do
    user
    group { nil } # a global snapshot by default
    points { 100 }
    rank_position { 1 }
    snapshot_at { Time.current }

    # A group-scoped snapshot row.
    trait :for_group do
      group
    end
  end
end
