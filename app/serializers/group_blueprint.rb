# frozen_string_literal: true

# Group projection for the authenticated group endpoints. `code` is the invite
# code, exposed because every consumer here is already a member (the controller
# gates on membership/ownership). member_count and is_owner are computed from
# options so callers can avoid an N+1: pass member_counts (a {group_id => count}
# hash) for collections, and current_user for is_owner.
class GroupBlueprint < Blueprinter::Base
  identifier :id

  fields :name, :description, :code, :is_general_pool, :created_at

  field :member_count do |group, options|
    counts = options[:member_counts]
    counts ? counts.fetch(group.id, 0) : group.memberships.count
  end

  field :is_owner do |group, options|
    current_user = options[:current_user]
    !current_user.nil? && group.owner_id == current_user.id
  end
end
