class AddCachedLabelsList < ActiveRecord::Migration[7.0]
  def change
    add_column :conversations, :cached_label_list, :string
    Conversation.reset_column_information
    return unless defined?(ActsAsTaggableOn::Taggable::Cache)

    ActsAsTaggableOn::Taggable::Cache.included(Conversation)
  end
end
