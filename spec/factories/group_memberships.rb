# frozen_string_literal: true

FactoryBot.define do
  factory :group_membership do
    group
    user
  end
end
