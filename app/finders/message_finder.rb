class MessageFinder
  def initialize(conversation, params)
    @conversation = conversation
    @params = params
  end

  def perform
    current_messages
  end

  private

  def conversation_messages
    @conversation.messages.includes(:attachments, :sender, sender: { avatar_attachment: [:blob] })
  end

  def messages
    return conversation_messages if @params[:filter_internal_messages].blank?

    conversation_messages.where.not('private = ? OR message_type = ?', true, 2)
  end

  def current_messages
    if @params[:after].present? && @params[:before].present?
      messages_between(@params[:after].to_i, @params[:before].to_i)
    elsif @params[:before].present?
      messages_before(@params[:before].to_i)
    elsif @params[:after].present?
      messages_after(@params[:after].to_i)
    else
      messages_latest
    end
  end

  def messages_after(after_id)
    messages
      .where('id > ?', after_id)
      .reorder(Arel.sql('created_at ASC, id ASC'))
      .limit(100)
  end

  def messages_before(before_id)
    messages
      .where('id < ?', before_id)
      .reorder(Arel.sql('created_at DESC, id DESC'))
      .limit(20)
      .to_a
      .reverse
  end

  def messages_between(after_id, before_id)
    messages
      .where('id >= ? AND id < ?', after_id, before_id)
      .reorder(Arel.sql('created_at ASC, id ASC'))
      .limit(1000)
  end

  def messages_latest
    messages
      .reorder(Arel.sql('created_at DESC, id DESC'))
      .limit(20)
      .to_a
      .reverse
  end
end
