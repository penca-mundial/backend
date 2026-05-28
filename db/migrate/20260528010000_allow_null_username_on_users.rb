# frozen_string_literal: true

# OAuth-provisioned users land with no username (they pick one in the
# onboarding flow after the first Google callback). The uniqueness index stays
# in place — Postgres treats NULL as distinct, so it doesn't get in the way.
class AllowNullUsernameOnUsers < ActiveRecord::Migration[8.1]
  def change
    change_column_null :users, :username, true
  end
end
