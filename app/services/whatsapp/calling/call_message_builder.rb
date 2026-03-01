# frozen_string_literal: true

# Service to create and manage WhatsApp call messages
# These are special messages that represent call lifecycle events
class Whatsapp::Calling::CallMessageBuilder
  def initialize(conversation:, whatsapp_call:)
    @conversation = conversation
    @whatsapp_call = whatsapp_call
    @inbox = conversation.inbox
    @account = conversation.account
  end

  # Create initial call message when call is initiated
  def create_initiated_message
    create_call_message(
      call_status: :initiated,
      content: 'Call initiated',
      metadata: {
        call_id: @whatsapp_call.call_id,
        call_direction: @whatsapp_call.direction,
        whatsapp_call_sid: @whatsapp_call.whatsapp_call_sid,
        initiated_at: @whatsapp_call.initiated_at&.to_i
      }
    )
  end

  # Update message when call is connected/answered
  def create_connected_message(_initiated_message = nil)
    # If there's an initiated message, we could update it, but for clarity
    # we create a new one to mark the connection
    create_call_message(
      call_status: :connected,
      content: 'Call connected',
      metadata: {
        call_id: @whatsapp_call.call_id,
        call_direction: @whatsapp_call.direction,
        whatsapp_call_sid: @whatsapp_call.whatsapp_call_sid,
        initiated_at: @whatsapp_call.initiated_at&.to_i,
        connected_at: @whatsapp_call.connected_at&.to_i
      }
    )
  end

  # Create final call message when call completes successfully
  # Recording will be attached separately by the terminate service
  def create_completed_message(_attachment = nil)
    duration = calculate_duration

    create_call_message(
      call_status: :completed,
      content: "Call completed (#{format_duration(duration)})",
      call_duration: duration,
      metadata: {
        call_id: @whatsapp_call.call_id,
        call_direction: @whatsapp_call.direction,
        whatsapp_call_sid: @whatsapp_call.whatsapp_call_sid,
        initiated_at: @whatsapp_call.initiated_at&.to_i,
        connected_at: @whatsapp_call.connected_at&.to_i,
        ended_at: @whatsapp_call.ended_at&.to_i,
        recording_url: @whatsapp_call.recording_url,
        recording_duration: duration
      }
    )
  end

  # Create message for unsuccessful call
  def create_failed_message(reason:, error_code: nil, error_message: nil)
    call_status = determine_failed_status(reason, error_code, error_message)

    create_call_message(
      call_status: call_status,
      content: status_to_message(call_status),
      metadata: {
        call_id: @whatsapp_call.call_id,
        call_direction: @whatsapp_call.direction,
        whatsapp_call_sid: @whatsapp_call.whatsapp_call_sid,
        initiated_at: @whatsapp_call.initiated_at&.to_i,
        ended_at: @whatsapp_call.ended_at&.to_i || Time.current.to_i,
        error_code: error_code,
        error_message: error_message
      }
    )
  end

  # Create message for Meta API errors
  def create_meta_error_message(error_code:, error_message:, meta_response: nil)
    call_status = Message.meta_error_to_call_status(error_code, error_message)

    create_call_message(
      call_status: call_status,
      content: status_to_message(call_status),
      metadata: {
        call_id: @whatsapp_call.call_id,
        call_direction: @whatsapp_call.direction,
        whatsapp_call_sid: @whatsapp_call.whatsapp_call_sid,
        initiated_at: @whatsapp_call.initiated_at&.to_i,
        ended_at: Time.current.to_i,
        error_code: error_code,
        error_message: error_message,
        meta_response: meta_response
      }
    )
  end

  private

  def create_call_message(call_status:, content:, call_duration: nil, metadata: {})
    # Determine sender based on call direction
    # For outbound calls, use the agent who initiated the call
    # For inbound calls, no sender (system message)
    is_outbound = @whatsapp_call.direction == 'outbound'
    sender = is_outbound ? @whatsapp_call.initiated_by_user : nil
    msg_type = determine_message_type

    Rails.logger.info "[CALL_MSG_BUILDER] Creating message - call_id=#{@whatsapp_call.call_id} call_status=#{call_status} content_type=voice_call message_type=#{msg_type} content=#{content.inspect} call_duration=#{call_duration.inspect} direction=#{@whatsapp_call.direction} sender_id=#{sender&.id} conversation_id=#{@conversation.id} metadata=#{metadata.inspect}"

    Message.create!(
      account: @account,
      inbox: @inbox,
      conversation: @conversation,
      message_type: msg_type,
      content_type: :voice_call,
      content: content,
      content_attributes: { call_id: @whatsapp_call.call_id },
      call_status: call_status,
      call_duration: call_duration,
      call_metadata: metadata,
      sender: sender,
      private: false,
      external_source_id_slack: @whatsapp_call.call_id
    )
  end

  def calculate_duration
    return @whatsapp_call.call_duration if @whatsapp_call.respond_to?(:call_duration) && @whatsapp_call.call_duration.present?
    return nil unless @whatsapp_call.connected_at.present? && @whatsapp_call.ended_at.present?

    (@whatsapp_call.ended_at - @whatsapp_call.connected_at).to_i
  end

  def calculate_call_duration
    calculate_duration
  end

  def format_duration(seconds)
    return '0s' unless seconds.to_i.positive?

    minutes = seconds / 60
    secs = seconds % 60
    return "#{secs}s" unless minutes.positive?

    "#{minutes}m #{secs}s"
  end

  def determine_failed_status(reason, error_code, error_message)
    # If we have Meta error codes, use them
    return Message.meta_error_to_call_status(error_code, error_message) if error_code.present?

    # Otherwise map reason to status
    case reason.to_s.downcase
    when 'rejected', 'declined'
      :rejected
    when 'missed', 'no_answer', 'timeout'
      :missed
    when 'cancelled', 'canceled'
      :cancelled
    when 'busy'
      :busy
    when 'no_connection', 'connection_failed', 'network_error'
      :no_connection
    else
      :failed
    end
  end

  def status_to_message(status)
    normalized_status = status.is_a?(String) ? status.to_sym : status

    case normalized_status
    when :rejected
      'Call rejected'
    when :missed
      'Call missed'
    when :cancelled
      'Call cancelled'
    when :busy
      'User busy'
    when :no_connection
      'Connection failed'
    when :unauthorized
      'Call failed: Not authorized'
    when :no_balance
      'Call failed: Insufficient balance'
    when :not_enabled
      'Call failed: Calling not enabled'
    when :rate_limit
      'Call failed: Rate limit exceeded'
    when :invalid
      'Call failed: Invalid parameters'
    when :other_meta_error
      'Call failed: Meta API error'
    else
      'Call failed'
    end
  end

  def determine_message_type
    @whatsapp_call.direction == 'outbound' ? 'outgoing' : 'incoming'
  end
end
