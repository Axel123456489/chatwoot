class AddSourceIdCreatedAtIndexToMessages < ActiveRecord::Migration[7.0]
  disable_ddl_transaction!

  INDEX_NAME = 'index_messages_on_source_id_and_created_at'.freeze

  def change
    return if index_exists?(:messages, [:source_id, :created_at], name: INDEX_NAME)

    add_index :messages, [:source_id, :created_at], name: INDEX_NAME, algorithm: :concurrently
  end
end
