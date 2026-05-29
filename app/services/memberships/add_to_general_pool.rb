# frozen_string_literal: true

module Memberships
  # Add a user to the general pool group. Idempotent: re-runs are no-ops
  # (the unique index on (group_id, user_id) is the source of truth).
  # Raises Penca::ServiceError if the general pool has not been seeded.
  class AddToGeneralPool < Service
    def initialize(user:)
      @user = user
    end

    def call
      pool = Group.find_by(is_general_pool: true)
      raise_service_error("General pool no inicializado.") if pool.nil?

      membership = GroupMembership.find_or_create_by!(group: pool, user: @user)
      success(membership)
    end
  end
end
