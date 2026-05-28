# frozen_string_literal: true

class GroupMembership < ApplicationRecord
  belongs_to :group, inverse_of: :memberships
  belongs_to :user

  validates :user_id, uniqueness: { scope: :group_id }
  validate :group_within_capacity, on: :create

  before_destroy :prevent_general_pool_removal

  private

  def group_within_capacity
    return unless group&.at_membership_capacity?

    errors.add(:base, :group_full)
  end

  def prevent_general_pool_removal
    return unless group&.is_general_pool?

    errors.add(:base, :cannot_leave_general_pool)
    throw :abort
  end
end
