# frozen_string_literal: true

class Whatsapp::Calling::WebhookSdpAnswerBroadcaster
  include Whatsapp::Calling::Concerns::CallFinder

  def initialize(account:, inbox:, call_id:, sdp_answer:)
    @account = account
    @inbox = inbox
    @call_id = call_id
    @sdp_answer = sdp_answer
  end

  def perform
    return if @sdp_answer.blank?

    conversation = find_conversation_by_call_id(@call_id)

    unless conversation
      Rails.logger.error(
        "[WHATSAPP_EVENTS] Conversation not found for call_id=#{@call_id} " \
        '(searched via CallFinder fallbacks)'
      )
      return
    end

    store_sdp_answer(conversation)
    broadcast_sdp_answer(conversation)
  rescue StandardError => e
    Rails.logger.error "[WHATSAPP_EVENTS] Failed to process SDP answer: #{e.message}"
    Rails.logger.error e.backtrace.join("\n")
  end

  private

  def store_sdp_answer(conversation)
    attrs = conversation.additional_attributes || {}
    whatsapp_call = attrs['whatsapp_call'] || {}

    whatsapp_call['whatsapp_sdp_answer'] = @sdp_answer
    whatsapp_call['sdp_answer_received_at'] = Time.current.to_i
    attrs['whatsapp_call'] = whatsapp_call

    conversation.update!(additional_attributes: attrs)
  end

  def broadcast_sdp_answer(conversation)
    ActionCable.server.broadcast(
      "account_#{@account.id}",
      {
        event: 'whatsapp_call_sdp_answer',
        data: {
          call_id: @call_id,
          conversation_id: conversation.id,
          account_id: @account.id,
          sdpAnswer: @sdp_answer
        }
      }
    )
  end
end
