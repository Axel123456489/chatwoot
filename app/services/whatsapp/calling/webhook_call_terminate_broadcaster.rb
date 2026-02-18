# frozen_string_literal: true

class Whatsapp::Calling::WebhookCallTerminateBroadcaster
  include Whatsapp::Calling::Concerns::CallFinder

  def initialize(account:, inbox:, call_data:)
    @account = account
    @inbox = inbox
    @call_data = call_data
    @call_id = call_data[:id]
  end

  def perform
    conversation = find_conversation_by_call_id(@call_id)

    unless conversation
      Rails.logger.error "[WHATSAPP_EVENTS] Terminate: no conversation found for call_id=#{@call_id}"
      return
    end

    broadcast(build_payload(conversation))
  rescue StandardError => e
    Rails.logger.error "[WHATSAPP_WEBHOOK_DEBUG] Failed to process terminate event: #{e.message}"
    Rails.logger.error "[WHATSAPP_WEBHOOK_DEBUG] Backtrace: #{e.backtrace.first(5).join("\n")}"
  end

  private

  def build_payload(conversation)
    {
      event: 'whatsapp_call_terminated',
      data: {
        account_id: @account.id,
        call_id: @call_id,
        conversation_id: conversation.display_id,
        status: @call_data[:status],
        duration: @call_data[:duration]
      }
    }
  end

  def broadcast(payload)
    ActionCable.server.broadcast(
      "account_#{@account.id}",
      payload
    )
  end
end
