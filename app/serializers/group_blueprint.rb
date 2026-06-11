# frozen_string_literal: true

# Group projection for the authenticated group endpoints. `code` is the invite
# code, exposed because every consumer here is already a member (the controller
# gates on membership/ownership). member_count and is_owner are computed from
# options so callers can avoid an N+1: pass member_counts (a {group_id => count}
# hash) for collections, and current_user for is_owner.
class GroupBlueprint < Blueprinter::Base
  identifier :id

  fields :name, :description, :code, :is_general_pool, :created_at

  # Who created the group. Callers must preload :owner (see GroupsController
  # index/show) so listing many groups stays N+1-free. A system owner (the
  # general pool's service account) is hidden — it must not be visible anywhere.
  field :owner_username do |group|
    owner = group.owner
    owner&.system? ? nil : owner&.username
  end

  field :member_count do |group, options|
    counts = options[:member_counts]
    counts ? counts.fetch(group.id, 0) : group.memberships.count
  end

  field :is_owner do |group, options|
    current_user = options[:current_user]
    !current_user.nil? && group.owner_id == current_user.id
  end

  # The current user's rank within this group (same definition as
  # /rankings/groups/:id), passed in as a {group_id => rank} hash. Only rendered
  # when callers opt in (groups/me); nil when the user has no ranked row yet.
  field :my_rank, if: ->(_field, _group, options) { options.key?(:my_ranks) } do |group, options|
    options[:my_ranks][group.id]
  end
end
