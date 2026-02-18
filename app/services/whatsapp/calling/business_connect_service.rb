# frozen_string_literal: true

# Service to handle WhatsApp "connect" event
# This is triggered when the user answers the call
# Responsibilities:
# - Store WhatsApp SDP answer for browser
# - Start call recording if enabled
# - Update call state to connected
# - Broadcast connection event
class Whatsapp::Calling::BusinessConnectService
  include Whatsapp::Calling::Concerns::Broadcastable

  def initialize(account:, inbox:, conversation:, call_data:)
    @account = account
    @inbox = inbox
    @conversation = conversation
    @call_data = call_data
    @call_id = call_data['id'] || call_data[:id]
  end

  def perform
    # Get SDP answer from WhatsApp
    sdp_answer = @call_data.dig('session', 'sdp') || @call_data.dig(:session, :sdp)

    unless sdp_answer
      Rails.logger.error '[BusinessConnect] No SDP answer in connect event'
      return { success: false, error: 'No SDP answer in connect event' }
    end

    # Find or create WhatsappCall record
    whatsapp_call = find_or_create_call_record

    # Mark recording as enabled in database
    whatsapp_call.update!(metadata: whatsapp_call.metadata.merge(recording_requested: true)) if whatsapp_call&.recording_enabled

    # Update conversation state with SDP answer
    update_conversation_state(sdp_answer)

    # Broadcast to frontend
    broadcast_connection_event

    { success: true }
  rescue StandardError => e
    Rails.logger.error "[BusinessConnect] Failed to process connect event: #{e.message}"
    Rails.logger.error e.backtrace.first(3).join("\n")
    { success: false, error: e.message }
  end

  private

  def find_or_create_call_record
    # First try to find by call_id
    call = WhatsappCall.find_by(call_id: @call_id)

    if call
      # Update to connected state
      call.connect! if call.may_connect?
      return call
    end

    # If not found, try to find by conversation (for legacy calls without WhatsappCall record)
    call = WhatsappCall.find_by(conversation: @conversation, status: %w[initiated ringing accepted])

    if call
      # Update call_id and connect
      call.update!(call_id: @call_id) if call.call_id != @call_id
      call.connect! if call.may_connect?
      return call
    end

    Rails.logger.warn "[BusinessConnect] No WhatsappCall record found for call #{@call_id}"
    nil
  rescue StandardError => e
    Rails.logger.error "[BusinessConnect] Error finding/updating call record: #{e.message}"
    nil
  end

  def update_conversation_state(sdp_answer)
    attrs = @conversation.additional_attributes || {}
    whatsapp_call = attrs['whatsapp_call'] || {}

    # Store WhatsApp SDP answer for browser retrieval
    whatsapp_call['sdp_answer'] = sdp_answer
    whatsapp_call['status'] = 'connected'
    whatsapp_call['connected_at'] = Time.current.to_i

    attrs['whatsapp_call'] = whatsapp_call
    attrs['call_status'] = 'connected'
    # CRITICAL: Preserve call_id at top level for terminate webhook lookup
    attrs['call_id'] = @call_id if @call_id.present?

    @conversation.update!(additional_attributes: attrs)
  end

  def broadcast_connection_event
    broadcast_call_connected(@conversation, @call_id)
  end
end
