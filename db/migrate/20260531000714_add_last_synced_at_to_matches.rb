class AddLastSyncedAtToMatches < ActiveRecord::Migration[8.1]
  def change
    add_column :matches, :last_synced_at, :datetime
    add_index :matches, :last_synced_at
  end
end
