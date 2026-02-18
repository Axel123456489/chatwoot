# Preloads expensive conversation metadata (latest messages, unread counts) in bulk
# to avoid N+1 queries when rendering conversation lists.
class Conversations::OpenConversationPreloader
  def initialize(conversations)
    @conversations = Array(conversations)
  end

  def preload!
    grouped_conversations.each do |account_id, conversations|
      preload_latest_messages(account_id, conversations)
      preload_latest_non_activity_messages(account_id, conversations)
      preload_unread_counts(account_id, conversations)
    end

    @conversations
  end

  private

  def grouped_conversations
    @grouped_conversations ||= @conversations.group_by(&:account_id)
  end

  def preload_latest_messages(account_id, conversations)
    conversations_by_id = conversations.index_by(&:id)
    conversation_ids = conversations_by_id.keys

    return if conversation_ids.empty?

    messages = Message.unscoped
                      .where(conversation_id: conversation_ids, account_id: account_id)
                      .select('DISTINCT ON (conversation_id) messages.*')
                      .order(Arel.sql('conversation_id, messages.created_at DESC, messages.id DESC'))
                      .includes(attachments: { file_attachment: :blob })

    messages.each do |message|
      conversation = conversations_by_id[message.conversation_id]
      next unless conversation

      message.define_singleton_method(:conversation) { conversation }
      conversation.latest_account_message = message
    end
  end

  def preload_latest_non_activity_messages(account_id, conversations)
    conversations_by_id = conversations.index_by(&:id)
    conversation_ids = conversations_by_id.keys

    return if conversation_ids.empty?

    messages = Message.unscoped
                      .where(conversation_id: conversation_ids, account_id: account_id)
                      .where.not(message_type: Message.message_types[:activity])
                      .select('DISTINCT ON (conversation_id) messages.*')
                      .order(Arel.sql('conversation_id, messages.created_at DESC, messages.id DESC'))
                      .includes(attachments: { file_attachment: :blob })

    messages.each do |message|
      conversation = conversations_by_id[message.conversation_id]
      next unless conversation

      message.define_singleton_method(:conversation) { conversation }
      conversation.latest_non_activity_message = message
    end
  end

  def preload_unread_counts(account_id, conversations)
    conversations_by_id = conversations.index_by(&:id)
    conversation_ids = conversations_by_id.keys

    return if conversation_ids.empty?

    unread_counts = Message.unscoped
                           .joins('INNER JOIN conversations ON conversations.id = messages.conversation_id')
                           .where(conversation_id: conversation_ids, account_id: account_id)
                           .where(message_type: Message.message_types[:incoming])
                           .where('messages.created_at > COALESCE(conversations.agent_last_seen_at, ?)', Time.at(0).utc)
                           .group(:conversation_id)
                           .count

    conversations.each do |conversation|
      count = unread_counts.fetch(conversation.id, 0)
      conversation.preloaded_unread_incoming_count = [count, 10].min
    end
  end
end
