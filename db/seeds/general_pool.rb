# frozen_string_literal: true

# The general pool is the implicit group every user belongs to. It is owned by
# the system user so that the `owner_id NOT NULL` foreign key holds without
# coupling the pool to any real user. Only one such group can exist (enforced
# by a partial unique index on is_general_pool = true).
module Seeds
  module GeneralPool
    NAME = "Penca general"

    def self.call
      owner = User.find_by!(email: Seeds::SystemUser::EMAIL)

      # unscoped so that a soft-deleted pool (if any) is still surfaced; the
      # partial unique index would otherwise refuse a fresh insert.
      ::Group.unscoped.find_or_create_by!(is_general_pool: true) do |group|
        group.owner = owner
        group.name  = NAME
      end
    end
  end
end
