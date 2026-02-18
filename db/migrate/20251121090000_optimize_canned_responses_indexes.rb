class OptimizeCannedResponsesIndexes < ActiveRecord::Migration[7.0]
  disable_ddl_transaction!

  def up
    unless index_exists?(:canned_responses, :account_id)
      add_index :canned_responses, :account_id,
                name: :index_canned_responses_on_account_id,
                algorithm: :concurrently
    end

    if column_exists?(:canned_responses,
                      :custom_role_id) && !index_exists?(:canned_responses, :custom_role_id) && !index_exists?(:canned_responses, :custom_role_id)
      add_index :canned_responses, :custom_role_id,
                name: :index_canned_responses_on_custom_role_id,
                algorithm: :concurrently
    end

    execute <<~SQL.squish
      CREATE INDEX CONCURRENTLY IF NOT EXISTS index_canned_responses_on_short_code_trgm
      ON canned_responses USING gin (short_code gin_trgm_ops);
    SQL

    execute <<~SQL.squish
      CREATE INDEX CONCURRENTLY IF NOT EXISTS index_canned_responses_on_content_trgm
      ON canned_responses USING gin (content gin_trgm_ops);
    SQL
  end

  def down
    execute <<~SQL.squish
      DROP INDEX CONCURRENTLY IF EXISTS index_canned_responses_on_account_id;
    SQL

    execute <<~SQL.squish
      DROP INDEX CONCURRENTLY IF EXISTS index_canned_responses_on_custom_role_id;
    SQL

    execute <<~SQL.squish
      DROP INDEX CONCURRENTLY IF EXISTS index_canned_responses_on_short_code_trgm;
    SQL

    execute <<~SQL.squish
      DROP INDEX CONCURRENTLY IF EXISTS index_canned_responses_on_content_trgm;
    SQL
  end
end
