# frozen_string_literal: true

module Groups
  # Rotates a group's invite code (e.g. after it leaks). Only the owner may do
  # it. The unique-code generation lives on the model (Group#regenerate_code!),
  # so it is not duplicated here.
  class RegenerateCode < Service
    def initialize(owner:, group:)
      @owner = owner
      @group = group
    end

    def call
      raise_service_error(I18n.t("services.groups.not_owner")) unless @group.owner_id == @owner.id

      @group.regenerate_code!
      success(group: @group)
    end
  end
end
