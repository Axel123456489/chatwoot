# frozen_string_literal: true

module Whatsapp::Calling::Concerns::CallFinder
  extend ActiveSupport::Concern

  private

  # Find conversation by call_id with multiple fallback strategies
  def find_conversation_by_call_id(call_id)
    # Try by identifier (for inbound calls)
    conversation = @account.conversations.find_by(identifier: call_id)
    return conversation if conversation

    # Try by additional_attributes['call_id'] (current storage)
    conversation = @account.conversations.where("additional_attributes ->> 'call_id' = ?", call_id).first
    return conversation if conversation

    # Try by additional_attributes['whatsapp_call']['call_id'] (alternative location)
    conversation = @account.conversations.where("additional_attributes -> 'whatsapp_call' ->> 'call_id' = ?", call_id).first
    return conversation if conversation

    # Try by additional_attributes['id'] (for outbound calls)
    conversation = @account.conversations.where("additional_attributes ->> 'id' = ?", call_id).first
    return conversation if conversation

    # Try by additional_attributes['whatsapp_call']['id'] (alternative location)
    conversation = @account.conversations.where("additional_attributes -> 'whatsapp_call' ->> 'id' = ?", call_id).first
    return conversation if conversation

    # Try by message call_metadata (for inbound calls)
    @account.conversations.joins(:messages)
            .where("messages.call_metadata->>'call_id' = ?", call_id)
            .first
  end

  # Find WhatsappCall record by call_id and conversation
  # With fallback to find by conversation only (for outbound calls where call_id might not match yet)
  def find_whatsapp_call(call_id:, conversation:)
    # First try: exact call_id match
    whatsapp_call = WhatsappCall.includes(:account, :inbox, :contact)
                                .find_by(call_id: call_id, conversation: conversation)
    return whatsapp_call if whatsapp_call

    # Fallback for outbound calls: if call_id not found, try to find by conversation
    # This handles the case where webhook arrives before setup_webrtc updates the call_id
    whatsapp_call = WhatsappCall.for_conversation(conversation.id)
                                .outbound
                                .recent
                                .includes(:account, :inbox, :contact)
                                .first

    if whatsapp_call && whatsapp_call.call_id != call_id
      ActiveRecord::Base.transaction do
        old_call_id = whatsapp_call.call_id
        whatsapp_call.update!(call_id: call_id)
        update_message_call_id_for_fallback(conversation, old_call_id, call_id)
      end
    end

    whatsapp_call
  end

  # Helper to update message call_id when using fallback search
  def update_message_call_id_for_fallback(conversation, old_call_id, new_call_id)
    message = conversation.messages
                          .where(content_type: :voice_call)
                          .where("call_metadata->>'call_id' = ?", old_call_id)
                          .first

    return unless message

    metadata = message.call_metadata.merge('call_id' => new_call_id, 'whatsapp_call_sid' => new_call_id)
    message.update!(call_metadata: metadata)
  end

  # Find WhatsappCall record by call_id only
  def find_whatsapp_call_by_id(call_id)
    WhatsappCall.includes(:account, :inbox, :contact, :conversation)
                .find_by(call_id: call_id)
  end

  # Update or create WhatsappCall record
  def ensure_whatsapp_call(call_id:, conversation:, **attributes)
    whatsapp_call = find_whatsapp_call(call_id: call_id, conversation: conversation)

    if whatsapp_call
      whatsapp_call.update!(attributes)
    else
      whatsapp_call = WhatsappCall.create!(
        call_id: call_id,
        conversation: conversation,
        **attributes
      )
    end

    whatsapp_call
  end
end
