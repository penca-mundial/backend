# frozen_string_literal: true

module Users
  # Update the editable profile fields (timezone, avatar_url, username) of
  # the given user. Forbidden fields (email, admin, system, banned_at) are
  # filtered both at the controller (strong params) and here, so a buggy
  # caller can't accidentally escalate privileges.
  class UpdateProfile < Service
    ALLOWED_FIELDS = %i[timezone avatar_url username].freeze

    def initialize(user:, attributes:)
      @user       = user
      @attributes = attributes.to_h.symbolize_keys.slice(*ALLOWED_FIELDS)
    end

    def call
      @user.update!(@attributes)
      success(@user)
    end
  end
end
