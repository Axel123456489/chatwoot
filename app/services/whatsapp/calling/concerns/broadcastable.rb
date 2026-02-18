# frozen_string_literal: true

module Whatsapp::Calling::Concerns::Broadcastable
  extend ActiveSupport::Concern

  private

  # Broadcast call event to account channel
  def broadcast_to_account(event_name, data)
    ActionCable.server.broadcast(
      "account_#{@account.id}",
      {
        event: event_name,
        data: data
      }
    )
  end

  # Broadcast call event to specific conversation
  def broadcast_to_conversation(conversation, event_name, data)
    tokens = (conversation.inbox.members + conversation.account.administrators)
             .pluck(:pubsub_token).uniq

    ActionCableBroadcastJob.perform_later(
      tokens,
      event_name,
      data.merge(conversation_id: conversation.display_id)
    )
  end

  # Broadcast call termination event
  def broadcast_call_terminated(conversation, call_id, status: nil, duration: nil)
    broadcast_to_account('whatsapp_call_terminated', {
                           account_id: @account.id,
                           call_id: call_id,
                           conversation_id: conversation.display_id,
                           status: status,
                           duration: duration
                         })
  end

  # Broadcast call connected event
  def broadcast_call_connected(conversation, call_id)
    broadcast_to_account('whatsapp_call_connected', {
                           account_id: @account.id,
                           call_id: call_id,
                           conversation_id: conversation.display_id,
                           status: 'connected'
                         })
  end

  # Broadcast SDP answer ready event
  def broadcast_sdp_answer(conversation, call_id, sdp_answer)
    broadcast_to_conversation(conversation, 'whatsapp_call_sdp_answer', {
                                call_id: call_id,
                                sdp_answer: sdp_answer,
                                account_id: @account.id
                              })
  end
end
