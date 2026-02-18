class AddOpenConversationIndexes < ActiveRecord::Migration[7.0]
  disable_ddl_transaction!

  OPEN_STATUSES = [Conversation.statuses[:open], Conversation.statuses[:pending], Conversation.statuses[:snoozed]].freeze

  def up
    add_index :conversations,
              [:account_id, :status, :last_activity_at],
              order: { last_activity_at: :desc },
              where: "status IN (#{OPEN_STATUSES.join(',')})",
              algorithm: :concurrently,
              name: :index_conversations_on_account_status_last_activity_open

    add_index :conversations,
              [:account_id, :assignee_id, :status, :last_activity_at],
              order: { last_activity_at: :desc },
              where: "status IN (#{OPEN_STATUSES.join(',')}) AND assignee_id IS NOT NULL",
              algorithm: :concurrently,
              name: :index_conversations_on_account_assignee_status_activity_open

    add_index :conversations,
              [:account_id, :status, :last_activity_at],
              order: { last_activity_at: :desc },
              where: "status IN (#{OPEN_STATUSES.join(',')}) AND assignee_id IS NULL",
              algorithm: :concurrently,
              name: :index_conversations_on_account_status_activity_unassigned_open

    add_index :conversations,
              [:account_id, :inbox_id, :status, :last_activity_at],
              order: { last_activity_at: :desc },
              where: "status IN (#{OPEN_STATUSES.join(',')})",
              algorithm: :concurrently,
              name: :index_conversations_on_account_inbox_status_activity_open
  end

  def down
    remove_index :conversations, name: :index_conversations_on_account_status_last_activity_open if index_exists?(:conversations,
                                                                                                                  name: :index_conversations_on_account_status_last_activity_open)
    remove_index :conversations, name: :index_conversations_on_account_assignee_status_activity_open if index_exists?(:conversations,
                                                                                                                      name: :index_conversations_on_account_assignee_status_activity_open)
    remove_index :conversations, name: :index_conversations_on_account_status_activity_unassigned_open if index_exists?(:conversations,
                                                                                                                        name: :index_conversations_on_account_status_activity_unassigned_open)
    remove_index :conversations, name: :index_conversations_on_account_inbox_status_activity_open if index_exists?(:conversations,
                                                                                                                   name: :index_conversations_on_account_inbox_status_activity_open)
  end
end
