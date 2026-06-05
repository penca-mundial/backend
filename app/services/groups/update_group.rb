# frozen_string_literal: true

module Groups
  # Updates a group's editable attributes (name, description). Authorization
  # (owner-only) is the controller's concern; this service just persists, so the
  # write stays out of the controller. The model validates name length, surfaced
  # as a failed ServiceResult.
  class UpdateGroup < Service
    def initialize(group:, name: nil, description: nil)
      @group = group
      @attributes = { name: name, description: description }.compact
    end

    def call
      @group.update!(@attributes)
      success(group: @group)
    end
  end
end
