# frozen_string_literal: true

class CreateGroups < ActiveRecord::Migration[8.1]
  def change
    create_table :groups do |t|
      t.references :owner, null: false, foreign_key: { to_table: :users }
      t.string   :name, null: false
      t.text     :description
      t.string   :code, null: false, limit: 8
      t.boolean  :is_general_pool, null: false, default: false
      t.datetime :deleted_at

      t.timestamps
    end

    add_index :groups, :code, unique: true
    add_index :groups, :is_general_pool,
              unique: true,
              where: "is_general_pool = true",
              name: "index_groups_on_single_general_pool"
    add_index :groups, :deleted_at
  end
end
