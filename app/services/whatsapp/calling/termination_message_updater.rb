# frozen_string_literal: true

class Whatsapp::Calling::TerminationMessageUpdater
  include Whatsapp::Calling::Concerns::Loggable

  def initialize(whatsapp_call:, status:)
    @whatsapp_call = whatsapp_call
    @status = status
  end

  def perform
    conversation = @whatsapp_call.conversation

    log_attempt(conversation.id)
    initiated_message = find_initiated_message(conversation)
    return log_missing(conversation.id) unless initiated_message

    log_found(initiated_message)
    call_status = map_webhook_status_to_call_status(@status)
    status_message = status_message_for(call_status)

    log_updating(initiated_message, call_status, status_message)
    changes = apply_update(initiated_message, call_status, status_message)
    log_saved(initiated_message.id, changes)
    dispatch_message_updated(initiated_message, changes)
    log_dispatched(initiated_message.id, call_status)
  rescue StandardError => e
    log_error('Failed to update termination message', exception: e, call_id: @whatsapp_call.call_id)
    raise
  end

  private

  def find_initiated_message(conversation)
    # NOTE: enum key is :initiated (not :call_initiated) because enum has _prefix: true
    conversation.messages
                .where(content_type: :voice_call)
                .where("call_metadata->>'call_id' = ?", @whatsapp_call.call_id)
                .where(call_status: :initiated)
                .first
  end

  def log_attempt(conversation_id)
    log_info(
      'Attempting to update termination message',
      call_id: @whatsapp_call.call_id,
      status: @status,
      conversation_id: conversation_id
    )
  end

  def log_missing(conversation_id)
    log_warn(
      'No initiated message found to update',
      call_id: @whatsapp_call.call_id,
      conversation_id: conversation_id
    )
  end

  def log_found(message)
    log_info(
      'Found initiated message to update',
      message_id: message.id,
      current_status: message.call_status,
      current_content: message.content
    )
  end

  def log_updating(message, call_status, status_message)
    log_info(
      'Updating message',
      message_id: message.id,
      from_status: message.call_status,
      to_status: call_status,
      new_content: status_message
    )
  end

  def log_saved(message_id, changes)
    log_info('Message saved, changes captured', message_id: message_id, changes: changes.keys)
  end

  def log_dispatched(message_id, call_status)
    log_info('Dispatched message.updated event', message_id: message_id, status: call_status)
  end

  def map_webhook_status_to_call_status(status)
    # NOTE: enum has _prefix: true so keys are without the call_ prefix
    case status.to_s.upcase
    when 'REJECTED' then :rejected
    when 'MISSED' then :missed
    when 'CANCELLED', 'CANCELED' then :cancelled
    when 'BUSY' then :busy
    else :failed
    end
  end

  def status_message_for(call_status)
    case call_status
    when :rejected then 'Call rejected'
    when :missed then 'Missed call'
    when :cancelled then 'Call cancelled'
    when :busy then 'Contact was busy'
    else 'Call failed'
    end
  end

  def apply_update(message, call_status, status_message)
    message.call_status = call_status
    message.content = status_message
    message.call_metadata = (message.call_metadata || {}).merge(
      ended_at: @whatsapp_call.ended_at&.to_i || Time.current.to_i
    )

    message.save!
    message.previous_changes
  end

  def dispatch_message_updated(message, changes)
    Rails.configuration.dispatcher.dispatch(
      'message.updated',
      Time.zone.now,
      message: message,
      performed_by: nil,
      previous_changes: changes
    )
  end
end
