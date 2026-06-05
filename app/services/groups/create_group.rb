# frozen_string_literal: true

module Groups
  # Creates a user-owned group and adds the owner as its first member, atomically.
  #
  # All the invariants live on the model: Group#assign_code generates the unique
  # 8-char code, Group#enforce_owner_group_limit caps owned groups (raising via
  # `throw :abort`, surfaced by Service.call), and the length/format validations
  # guard name/code. This service does not re-implement any of them — it just
  # persists the group and the owner's membership in one transaction.
  class CreateGroup < Service
    def initialize(owner:, name:, description: nil)
      @owner = owner
      @name = name
      @description = description
    end

    def call
      group = nil

      ActiveRecord::Base.transaction do
        group = Group.new(owner: @owner, name: @name, description: @description)
        group.save! # triggers assign_code, the owner-limit guard, and validations
        GroupMembership.create!(group: group, user: @owner)
      end

      success(group: group)
    end
  end
end
