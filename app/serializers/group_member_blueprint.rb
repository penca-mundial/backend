# frozen_string_literal: true

# One row of a group's member list. Serializes a GroupMembership into a compact
# user (no email or other credentials) plus joined_at and is_owner. is_owner is
# computed from the owner_id option so the whole list shares one value instead of
# loading the group per row.
class GroupMemberBlueprint < Blueprinter::Base
  # Compact public user info for a member row.
  class User < Blueprinter::Base
    identifier :id

    fields :username, :avatar_url
  end

  fields :joined_at

  field :is_owner do |membership, options|
    membership.user_id == options[:owner_id]
  end

  association :user, blueprint: User
end
