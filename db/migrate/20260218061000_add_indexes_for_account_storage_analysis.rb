# frozen_string_literal: true

class AddIndexesForAccountStorageAnalysis < ActiveRecord::Migration[7.0]
  disable_ddl_transaction!

  def change
    add_index :active_storage_attachments, :blob_id,
              algorithm: :concurrently, if_not_exists: true
    add_index :active_storage_attachments, %i[record_type record_id],
              algorithm: :concurrently, if_not_exists: true
    add_index :active_storage_attachments, %i[record_type name],
              algorithm: :concurrently, if_not_exists: true
  end
end
