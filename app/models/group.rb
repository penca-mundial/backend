# frozen_string_literal: true

class Group < ApplicationRecord
  include SoftDeletable

  MAX_OWNED_GROUPS = 3
  MAX_MEMBERSHIPS = 500
  CODE_FORMAT = /\A[A-Z0-9]{8}\z/

  has_paper_trail

  belongs_to :owner, class_name: "User"

  has_many :memberships, class_name: "GroupMembership", inverse_of: :group
  has_many :users, through: :memberships

  default_scope { where(deleted_at: nil) }

  validates :name, length: { in: 3..50 }
  validates :code, format: { with: CODE_FORMAT }, uniqueness: true

  before_validation :assign_code, on: :create
  before_create :enforce_owner_group_limit

  # The general pool has no member cap; every other group is limited.
  def at_membership_capacity?
    return false if is_general_pool?

    memberships.count >= MAX_MEMBERSHIPS
  end

  private

  def assign_code
    return if code.present?

    self.code = loop do
      candidate = SecureRandom.alphanumeric(8).upcase
      break candidate unless Group.unscoped.exists?(code: candidate)
    end
  end

  def enforce_owner_group_limit
    return if is_general_pool?
    return if Group.where(owner_id: owner_id, is_general_pool: false).count < MAX_OWNED_GROUPS

    errors.add(:base, :too_many_owned_groups)
    throw :abort
  end
end
