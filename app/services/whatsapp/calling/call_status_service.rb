# frozen_string_literal: true

class Whatsapp::Calling::CallStatusService
  include Whatsapp::Calling::Concerns::Loggable
  include Whatsapp::Calling::Concerns::CallFinder

  STATUS_RINGING = 'RINGING'
  STATUS_ACCEPTED = 'ACCEPTED'
  STATUS_CONNECTED = 'CONNECTED'
  STATUS_MISSED = 'MISSED'
  STATUS_FAILED_GROUP = %w[REJECTED CANCELLED CANCELED BUSY FAILED].freeze
  STATUS_TERMINAL = (STATUS_FAILED_GROUP + [STATUS_MISSED]).freeze

  def initialize(account:, inbox:, status_data:, metadata:)
    @account = account
    @inbox = inbox
    @status_data = status_data
    @metadata = metadata
    @call_id = status_data['id']
    @status = status_data['status']
    @error_code = status_data['error_code']
    @error_message = status_data['error_message']
  end

  def perform
    Rails.logger.info "[CALL_STATUS] Incoming status event - call_id=#{@call_id} raw_status=#{@status} error_code=#{@error_code.inspect} error_message=#{@error_message.inspect} metadata=#{@metadata.inspect}"

    conversation = find_conversation
    unless conversation
      Rails.logger.warn "[CALL_STATUS] Conversation not found for call_id=#{@call_id}"
      return log_error('Conversation not found', call_id: @call_id)
    end

    whatsapp_call = find_whatsapp_call(call_id: @call_id, conversation: conversation)
    unless whatsapp_call
      Rails.logger.warn "[CALL_STATUS] WhatsappCall record not found for call_id=#{@call_id} conversation_id=#{conversation.id}"
      return log_error('WhatsappCall not found', call_id: @call_id)
    end

    call_status = map_whatsapp_status_to_call_status(@status)
    Rails.logger.info "[CALL_STATUS] Mapped status - call_id=#{@call_id} raw=#{@status} mapped=#{call_status} whatsapp_call_state=#{whatsapp_call.status} direction=#{whatsapp_call.direction}"

    update_conversation_status(conversation, whatsapp_call, call_status)
    update_whatsapp_call_status(whatsapp_call, call_status)

    if should_create_message?
      Rails.logger.info "[CALL_STATUS] Creating terminal status message - call_id=#{@call_id} call_status=#{call_status}"
      create_status_message(conversation, whatsapp_call, call_status)
    else
      Rails.logger.info "[CALL_STATUS] No message created for non-terminal status - call_id=#{@call_id} status=#{@status}"
    end
  rescue StandardError => e
    log_error('Failed to process call status', exception: e, call_id: @call_id, status: @status)
    # Don't re-raise to prevent job retry loops
  end

  private

  def find_conversation
    # First try by identifier (for inbound calls)
    @account.conversations.find_by(identifier: @call_id) ||
      find_conversation_by_call_id(@call_id)
  end

  def update_conversation_status(conversation, whatsapp_call, call_status)
    additional_attrs = conversation.additional_attributes || {}
    additional_attrs['call_status'] = call_status
    additional_attrs['call_direction'] = whatsapp_call.direction if whatsapp_call.direction.present?
    additional_attrs['status_updated_at'] = Time.current.to_i
    # CRITICAL: Preserve call_id at top level for terminate webhook lookup (outbound calls)
    additional_attrs['call_id'] = @call_id if @call_id.present?

    conversation.update!(additional_attributes: additional_attrs)
  end

  def update_whatsapp_call_status(whatsapp_call, call_status)
    # Skip if already in a terminal state
    return if whatsapp_call.ended?

    status = @status.to_s.upcase
    handle_ringing_status(whatsapp_call) if status == STATUS_RINGING
    handle_connected_status(whatsapp_call) if status == STATUS_ACCEPTED || status == STATUS_CONNECTED
    handle_terminal_status(whatsapp_call, call_status) if STATUS_TERMINAL.include?(status)
  end

  def handle_ringing_status(whatsapp_call)
    transition_to_state(whatsapp_call, :ring, 'ringing')
  end

  def handle_connected_status(whatsapp_call)
    # CRITICAL: WhatsApp sends ACCEPTED twice:
    # 1. When WebRTC connects (no SDP) - 'connect' event arrives first with SDP
    # 2. Few seconds later (with SDP in DB from 'connect' event)
    # Only transition to 'accepted' if we've received the SDP answer via 'connect' event
    if accepted_with_sdp?(whatsapp_call)
      # Multi-step transition: initiated -> ringing -> accepted -> connected
      transition_to_state(whatsapp_call, :ring, 'ringing') if whatsapp_call.initiated?
      transition_to_state(whatsapp_call, :accept, 'accepted')
      transition_to_state(whatsapp_call, :connect, 'connected')
    elsif whatsapp_call.initiated?
      # Just transition to ringing (WebRTC connected but client hasn't answered yet)
      transition_to_state(whatsapp_call, :ring, 'ringing')
    end
  end

  def handle_terminal_status(whatsapp_call, call_status)
    event = case call_status
            when 'rejected' then :reject
            when 'missed' then :timeout
            when 'cancelled' then :cancel
            else :fail
            end

    whatsapp_call.call_status_reason = call_status if event == :fail
    transition_to_state(whatsapp_call, event, call_status)
    store_error_details(whatsapp_call) if @error_code || @error_message

    # Update or create termination message for terminal states
    # This ensures the frontend sees the updated message even if terminate webhook doesn't arrive
    Whatsapp::Calling::TerminationMessageUpdater.new(whatsapp_call: whatsapp_call, status: call_status).perform
  end

  def transition_to_state(whatsapp_call, event, state_name)
    return unless whatsapp_call.public_send("may_#{event}?")

    whatsapp_call.public_send("#{event}!")
  rescue AASM::InvalidTransition
    log_warn("Cannot transition to #{state_name}", from: whatsapp_call.status, call_id: @call_id)
  end

  def store_error_details(whatsapp_call)
    whatsapp_call.with_lock do
      whatsapp_call.update!(
        error_code: @error_code,
        error_message: @error_message
      )
    end
  end

  def create_status_message(conversation, whatsapp_call, call_status)
    builder = Whatsapp::Calling::CallMessageBuilder.new(conversation: conversation, whatsapp_call: whatsapp_call)
    builder.create_failed_message(reason: call_status, error_code: @error_code, error_message: @error_message)
  end

  def accepted_with_sdp?(whatsapp_call)
    whatsapp_call.conversation.additional_attributes
                 &.dig('whatsapp_call', 'whatsapp_sdp_answer')
                 .present?
  end

  def map_whatsapp_status_to_call_status(status)
    case status.to_s.upcase
    when STATUS_RINGING
      'initiated'
    when STATUS_ACCEPTED, STATUS_CONNECTED
      'connected'
    when 'REJECTED'
      'rejected'
    when STATUS_MISSED
      'missed'
    when 'CANCELLED', 'CANCELED'
      'cancelled'
    when 'BUSY'
      'busy'
    else
      'failed'
    end
  end

  def should_create_message?
    STATUS_TERMINAL.include?(@status.to_s.upcase)
  end
end
