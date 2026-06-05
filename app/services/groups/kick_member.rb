# frozen_string_literal: true

module Groups
  # Removes another member from a group. Only the owner may kick, the owner can
  # never be kicked, and the target must actually be a member. The not-a-member
  # case is pre-checked here so the message is clean rather than a silent no-op.
  class KickMember < Service
    def initialize(owner:, group:, target_user:)
      @owner = owner
      @group = group
      @target_user = target_user
    end

    def call
      raise_service_error(I18n.t("services.groups.not_owner")) unless @group.owner_id == @owner.id
      raise_service_error(I18n.t("services.groups.cannot_kick_owner")) if @target_user.id == @owner.id

      membership = @group.memberships.find_by(user_id: @target_user.id)
      raise_service_error(I18n.t("services.groups.not_a_member")) if membership.nil?

      membership.destroy!
      success(group: @group)
    end
  end
end
