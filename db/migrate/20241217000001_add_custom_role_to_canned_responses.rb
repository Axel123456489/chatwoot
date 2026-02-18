class AddCustomRoleToCannedResponses < ActiveRecord::Migration[7.0]
  def change
    # Add custom_role_id to canned_responses table
    add_reference :canned_responses, :custom_role, optional: true, foreign_key: true

    # Remove folder_id column if it exists
    remove_column :canned_responses, :folder_id, :integer if column_exists?(:canned_responses, :folder_id)
  end
end
