# frozen_string_literal: true

class CreateGroupMemberships < ActiveRecord::Migration[8.1]
  def change
    create_table :group_memberships do |t|
      # group_id is covered by the composite unique index below.
      t.references :group, null: false, foreign_key: true, index: false
      t.references :user,  null: false, foreign_key: true
      t.datetime   :joined_at, null: false, default: -> { "CURRENT_TIMESTAMP" }

      t.timestamps
    end

    add_index :group_memberships, %i[group_id user_id], unique: true
  end
end
