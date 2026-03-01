# frozen_string_literal: true

class Whatsapp::Calling::CallTerminateService
  include Whatsapp::Calling::Concerns::Loggable
  include Whatsapp::Calling::Concerns::CallFinder
  include Whatsapp::Calling::Concerns::Broadcastable

  def initialize(account:, inbox:, call_data:, metadata: {}, call_id: nil)
    @account = account
    @inbox = inbox
    @call_data = call_data
    @metadata = metadata || {}
    @call_id = call_id || call_data['id']
  end

  def perform
    conversation = find_conversation
    return log_warn('Conversation not found', call_id: @call_id) unless conversation

    whatsapp_call = find_whatsapp_call(call_id: @call_id, conversation: conversation)
    return log_warn('WhatsappCall record not found', call_id: @call_id) unless whatsapp_call

    @current_whatsapp_call = whatsapp_call

    ActiveRecord::Base.transaction do
      update_whatsapp_call(whatsapp_call)
      recording_result = stop_recording(whatsapp_call)
      create_call_termination_message(conversation, whatsapp_call, recording_result)
      notify_termination(conversation)

      log_info('Call terminated', call_id: @call_id, status: whatsapp_call.status)
    end
  rescue StandardError => e
    log_error('Failed to terminate call', exception: e, call_id: @call_id)
    # Don't re-raise to prevent job retry loops
  end

  private

  def find_conversation
    find_conversation_by_call_id(@call_id)
  end

  def update_whatsapp_call(whatsapp_call)
    # Skip if already in a terminal state
    return if whatsapp_call.ended?

    if whatsapp_call.may_end_call?
      whatsapp_call.end_call!
    else
      log_warn('Forcing end state transition',
               from: whatsapp_call.status,
               call_id: @call_id)
      whatsapp_call.with_lock do
        whatsapp_call.update!(
          status: 'ended',
          ended_at: Time.current
        )
        whatsapp_call.send(:finalize_call)
      end
    end

    whatsapp_call.update!(call_duration: @call_data['duration'].to_i) if @call_data['duration']
  end

  def stop_recording(whatsapp_call)
    recording_service = Whatsapp::Calling::RecordingService.new(call: whatsapp_call)
    result = recording_service.stop

    if result[:success]
      whatsapp_call.update!(
        recording_url: result[:recording_url],
        recording_duration: result[:duration]
      )

      Whatsapp::Calling::ProcessRecordingsJob.perform_later
    end

    result
  rescue StandardError => e
    log_error('Error stopping recording', exception: e)
    { success: false, error: e.message }
  end

  def create_call_termination_message(conversation, whatsapp_call, recording_result)
    log_info('Creating call termination message',
             call_id: whatsapp_call.call_id,
             call_status: @call_data['status'],
             call_duration: @call_data['duration'],
             whatsapp_call_status: whatsapp_call.status,
             connected_at: whatsapp_call.connected_at,
             initiated_at: whatsapp_call.initiated_at,
             ended_at: whatsapp_call.ended_at)

    # Check if termination message already exists (webhook received multiple times)
    # NOTE: enum has _prefix: true, so real keys are :completed, :rejected, etc. (without call_ prefix)
    existing_termination = conversation.messages
                                       .where(content_type: :voice_call)
                                       .where("call_metadata->>'call_id' = ?", whatsapp_call.call_id)
                                       .where(call_status: %w[completed rejected missed cancelled busy no_connection failed
                                                              unauthorized no_balance not_enabled rate_limit invalid
                                                              other_meta_error])
                                       .first

    if existing_termination
      log_info('Termination message already exists, skipping', message_id: existing_termination.id)
      return existing_termination
    end

    builder = Whatsapp::Calling::CallMessageBuilder.new(
      conversation: conversation,
      whatsapp_call: whatsapp_call
    )

    call_status = @call_data['status']&.downcase
    call_duration = @call_data['duration'].to_i

    log_info('Determining call outcome',
             call_status: call_status,
             duration: call_duration,
             will_create_new: call_status == 'completed' && call_duration.positive?)

    # Determine if call was successful (connected AND had duration) or failed
    # WhatsApp only sends COMPLETED with positive duration when the call was truly answered.
    # Don't rely on connected_at — for outbound P2P calls it may not be set due to webhook timing.
    if call_status == 'completed' && call_duration.positive?
      # Call was answered - create NEW completed message with recording
      log_info('Call was answered, creating completed message with recording')
      message = builder.create_completed_message

      # Attach recording if available
      attach_recording_to_message(message, recording_result) if recording_result[:success] && recording_result[:blob].present?

      message
    else
      # Call was NOT answered or has no duration - UPDATE the existing "Call initiated..." message
      # Map COMPLETED with no duration to MISSED
      actual_reason = if call_status == 'completed' && call_duration.zero?
                        'missed'
                      else
                        determine_failure_reason(call_status, whatsapp_call)
                      end

      log_info('Call was not answered, updating initiated message to failed',
               call_status: call_status,
               duration: call_duration,
               reason: actual_reason)

      update_initiated_message_to_failed(conversation, whatsapp_call, actual_reason)
    end
  end

  def update_initiated_message_to_failed(conversation, whatsapp_call, reason)
    log_info('Attempting to update initiated message to failed',
             call_id: whatsapp_call.call_id,
             reason: reason,
             conversation_id: conversation.id)

    # Find the initiated message by call_id in metadata
    # NOTE: enum key is :initiated (not :call_initiated) because enum has _prefix: true
    initiated_message = conversation.messages
                                    .where(content_type: :voice_call)
                                    .where("call_metadata->>'call_id' = ?", whatsapp_call.call_id)
                                    .where(call_status: :initiated)
                                    .first

    if initiated_message
      log_info('Found initiated message',
               message_id: initiated_message.id,
               current_status: initiated_message.call_status)

      # Update existing message to failed status
      failed_status = determine_failed_call_status(reason)

      log_info('Updating message to failed status',
               message_id: initiated_message.id,
               failed_status: failed_status)

      # Assign attributes and save to capture changes
      initiated_message.call_status = failed_status
      initiated_message.content = status_to_failed_message(failed_status)
      initiated_message.call_metadata = initiated_message.call_metadata.merge(
        ended_at: whatsapp_call.ended_at&.to_i || Time.current.to_i,
        failure_reason: reason
      )
      initiated_message.save!

      # Capture changes and broadcast to frontend
      previous_changes = initiated_message.previous_changes

      log_info('Message saved, changes captured',
               message_id: initiated_message.id,
               changes: previous_changes.keys)

      Rails.configuration.dispatcher.dispatch(
        'message.updated',
        Time.zone.now,
        message: initiated_message,
        previous_changes: previous_changes
      )

      log_info('Updated initiated message to failed status and dispatched event',
               message_id: initiated_message.id,
               status: failed_status,
               previous_changes: previous_changes.keys)

      initiated_message
    else
      # Fallback: create new failed message if initiated message not found
      log_warn("Initiated message not found for call_id=#{whatsapp_call.call_id}, creating new failed message")
      builder = Whatsapp::Calling::CallMessageBuilder.new(
        conversation: conversation,
        whatsapp_call: whatsapp_call
      )
      builder.create_failed_message(reason: reason)
    end
  rescue StandardError => e
    log_error('Failed to update/create termination message',
              exception: e,
              call_id: whatsapp_call.call_id,
              reason: reason)
    nil
  end

  def determine_failed_call_status(reason)
    # NOTE: enum has _prefix: true so keys are without the call_ prefix
    case reason.to_s.downcase
    when 'rejected', 'declined'
      :rejected
    when 'missed', 'no_answer', 'timeout'
      :missed
    when 'cancelled', 'canceled'
      :cancelled
    when 'busy'
      :busy
    when 'no_connection', 'failed'
      :no_connection
    else
      :missed
    end
  end

  def status_to_failed_message(status)
    case status
    when :rejected
      'Call rejected'
    when :missed
      'Missed call'
    when :cancelled
      'Call cancelled'
    when :busy
      'User busy'
    when :no_connection
      'Connection failed'
    else
      'Call failed'
    end
  end

  def attach_recording_to_message(message, recording_result)
    blob = recording_result[:blob]
    duration = recording_result[:duration]

    # Update message metadata
    message.call_metadata ||= {}
    message.call_metadata['recording_duration'] = duration
    message.save!

    # Create attachment using ActiveStorage blob
    attachment = message.attachments.create!(
      file_type: :audio,
      account_id: @account.id
    )

    attachment.file.attach(blob)
  rescue ActiveStorage::IntegrityError => e
    log_error('Recording integrity check failed', exception: e, message_id: message.id)
  rescue ActiveStorage::FileNotFoundError => e
    log_error('Recording file not found', exception: e, message_id: message.id)
  rescue ActiveRecord::RecordInvalid => e
    log_error('Failed to save attachment', exception: e, message_id: message.id)
  rescue StandardError => e
    log_error('Failed to attach recording', exception: e, message_id: message.id)
  end

  def determine_failure_reason(call_status, whatsapp_call = nil)
    status = call_status.to_s.downcase
    call = whatsapp_call || @current_whatsapp_call
    call ||= WhatsappCall.find_by(call_id: @call_id) if @call_id
    connected = call&.connected_at.present?

    return connected ? 'cancelled' : 'missed' if status == 'completed'

    case status
    when 'rejected', 'declined'
      'rejected'
    when 'missed', 'no_answer'
      'missed'
    when 'cancelled', 'canceled'
      'cancelled'
    when 'busy'
      'busy'
    when 'failed'
      if call.nil?
        'failed'
      else
        (connected ? 'failed' : 'missed')
      end
    else
      'failed'
    end
  end

  def find_conversation
    # Try by identifier first
    conversation = @account.conversations.find_by(identifier: @call_id)
    return conversation if conversation

    # Try by additional_attributes['id'] (for outbound calls)
    conversation = @account.conversations.where("additional_attributes ->> 'id' = ?", @call_id).first
    return conversation if conversation

    # Try by additional_attributes['whatsapp_call']['id'] (alternative location)
    conversation = @account.conversations.where("additional_attributes -> 'whatsapp_call' ->> 'id' = ?", @call_id).first
    return conversation if conversation

    # Try by message call_metadata (for inbound calls)
    @account.conversations.joins(:messages)
            .where("messages.call_metadata->>'call_id' = ?", @call_id)
            .first
  end

  def notify_termination(conversation)
    broadcast_call_terminated(
      conversation,
      @call_id,
      status: @call_data['status'],
      duration: @call_data['duration']
    )
  end

  def format_duration(seconds)
    minutes = seconds / 60
    secs = seconds % 60
    "#{minutes}m #{secs}s"
  end
end
