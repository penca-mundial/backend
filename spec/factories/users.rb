# frozen_string_literal: true

FactoryBot.define do
  factory :user do
    sequence(:email) { |n| "user#{n}@example.com" }
    sequence(:username) { |n| "user_#{n}" }
    password { "Sup3rSecret" }
    confirmed_at { Time.current }

    trait :unconfirmed do
      confirmed_at { nil }
    end

    trait :admin do
      admin { true }
    end

    trait :banned do
      banned_at { Time.current }
    end

    # The service account: exists only to satisfy owner_id foreign keys and must
    # never be able to authenticate.
    trait :system do
      system { true }
      email { "system@penca.local" }
      sequence(:username) { |n| "system_#{n}" }
    end

    # OAuth-provisioned user: authenticated via Google, no explicit password.
    trait :oauth do
      provider { "google_oauth2" }
      sequence(:uid) { |n| "google-uid-#{n}" }
      password { nil }
    end
  end
end
