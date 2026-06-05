# frozen_string_literal: true

module Groups
  # Removes a user's own membership from a group. Idempotent: leaving a group the
  # user is not in succeeds without error. The general pool cannot be left, and
  # an owner cannot leave their own group — both are pre-checked here so the
  # message is clean (the model's before_destroy guard is only a safety net; an
  # aborted destroy would otherwise surface a generic message).
  class LeaveGroup < Service
    def initialize(user:, group:)
      @user = user
      @group = group
    end

    def call
      raise_service_error(cannot_leave_general_pool_message) if @group.is_general_pool?
      raise_service_error(I18n.t("services.groups.owner_cannot_leave")) if @group.owner_id == @user.id

      @group.memberships.find_by(user_id: @user.id)&.destroy!
      success(group: @group)
    end

    private

    def cannot_leave_general_pool_message
      I18n.t("activerecord.errors.models.group_membership.attributes.base.cannot_leave_general_pool")
    end
  end
end
