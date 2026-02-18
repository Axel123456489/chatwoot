class AddConversationCreatedAtIndexToMessages < ActiveRecord::Migration[7.0]
  disable_ddl_transaction!

  INDEX_NAME = 'index_messages_on_conversation_id_created_at_id_desc'.freeze

  def up
    execute <<~SQL.squish
      CREATE INDEX CONCURRENTLY IF NOT EXISTS #{INDEX_NAME}
      ON messages (conversation_id, created_at DESC, id DESC);
    SQL
  end

  def down
    execute <<~SQL.squish
      DROP INDEX CONCURRENTLY IF EXISTS #{INDEX_NAME};
    SQL
  end
end
