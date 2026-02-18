class AddContentTypeToCannedResponses < ActiveRecord::Migration[7.0]
  def change
    add_column :canned_responses, :content_type, :string, default: 'markdown', null: false
    add_index :canned_responses, :content_type
  end
end
