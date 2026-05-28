# frozen_string_literal: true

class AddCustomFieldsToUsers < ActiveRecord::Migration[8.1]
  def change
    change_table :users, bulk: true do |t|
      t.string   :username,   null: false
      t.string   :provider
      t.string   :uid
      t.string   :avatar_url
      t.string   :timezone,   null: false, default: "UTC"
      t.boolean  :admin,      null: false, default: false
      t.boolean  :system,     null: false, default: false
      t.datetime :banned_at
    end

    add_index :users, :username, unique: true
    add_index :users, %i[provider uid],
              unique: true,
              where: "provider IS NOT NULL",
              name: "index_users_on_provider_and_uid"
  end
end
