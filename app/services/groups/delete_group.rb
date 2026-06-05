# frozen_string_literal: true

module Groups
  # Soft-deletes a group. Only its owner may delete it, and the general pool can
  # never be deleted. The actual removal is the model's SoftDeletable#soft_delete!
  # (sets deleted_at; the default_scope then hides it).
  class DeleteGroup < Service
    def initialize(owner:, group:)
      @owner = owner
      @group = group
    end

    def call
      raise_service_error(I18n.t("services.groups.not_owner")) unless @group.owner_id == @owner.id
      raise_service_error(I18n.t("services.groups.cannot_delete_general_pool")) if @group.is_general_pool?

      @group.soft_delete!
      success(group: @group)
    end
  end
end
