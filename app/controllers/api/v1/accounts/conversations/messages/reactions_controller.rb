class Api::V1::Accounts::Conversations::Messages::ReactionsController < Api::V1::Accounts::Conversations::BaseController
  before_action :set_message

  def create
    return render_error('Emoji is required') if reaction_emoji.blank?

    update_reactions(add: true)
    send_to_whatsapp(reaction_emoji) if whatsapp_incoming?
    render json: message_response
  rescue StandardError => e
    Rails.logger.error "[Reactions] Error adding reaction: #{e.message}"
    render_error(e.message)
  end

  def destroy
    update_reactions(add: false)
    send_to_whatsapp('') if whatsapp_incoming?
    render json: message_response
  rescue StandardError => e
    Rails.logger.error "[Reactions] Error removing reaction: #{e.message}"
    render_error(e.message)
  end

  private

  def set_message
    @message = @conversation.messages.find(params[:message_id])
  end

  def reaction_emoji
    @reaction_emoji ||= params[:emoji]
  end

  def user_key
    "agent_#{Current.user.id}"
  end

  def update_reactions(add:)
    reactions = @message.content_attributes['reactions'] || {}

    if add
      reactions[user_key] = {
        'emoji' => reaction_emoji,
        'timestamp' => Time.current.to_i,
        'user_type' => 'agent',
        'user_id' => Current.user.id,
        'user_name' => Current.user.name
      }
    else
      reactions.delete(user_key)
    end

    @message.update!(content_attributes: @message.content_attributes.merge('reactions' => reactions))
  end

  def message_response
    {
      id: @message.id,
      content: @message.content,
      content_attributes: @message.content_attributes,
      conversation_id: @conversation.display_id
    }
  end

  def whatsapp_incoming?
    @conversation.inbox.channel_type == 'Channel::Whatsapp' &&
      @message.source_id.present? &&
      @message.incoming?
  end

  def send_to_whatsapp(emoji)
    @conversation.inbox.channel.send_reaction(
      @conversation.contact_inbox.source_id,
      @message.source_id,
      emoji
    )
  rescue StandardError => e
    Rails.logger.error "[Reactions] WhatsApp send failed: #{e.message}"
  end

  def render_error(message)
    render json: { success: false, error: message }, status: :unprocessable_entity
  end
end
