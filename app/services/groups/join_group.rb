# frozen_string_literal: true

module Groups
  # Adds a user to a group by its invite code. Idempotent: an existing member is
  # returned untouched. The 500-member cap is enforced by the model
  # (GroupMembership :group_full), so it is not re-checked here; the small TOCTOU
  # window on that cap is acceptable at this scale, so no row lock is taken.
  class JoinGroup < Service
    def initialize(user:, code:)
      @user = user
      @code = code
    end

    def call
      group = Group.find_by(code: normalized_code)
      # default_scope hides soft-deleted groups, so "not found" also covers them.
      raise_service_error(I18n.t("services.groups.not_found")) if group.nil?

      existing = group.memberships.find_by(user_id: @user.id)
      return success(membership: existing, joined: false) if existing

      membership = group.memberships.create!(user: @user)
      success(membership: membership, joined: true)
    end

    private

    def normalized_code
      @code.to_s.strip.upcase
    end
  end
end
