# frozen_string_literal: true

# Service to manage call state transitions and lifecycle
class Whatsapp::Calling::CallStateManager
  VALID_STATES = %w[
    initiated
    ringing
    accepted
    connecting
    connected
    holding
    ended
    failed
    rejected
    timeout
  ].freeze

  VALID_TRANSITIONS = {
    'initiated' => %w[ringing rejected failed timeout],
    'ringing' => %w[accepted rejected timeout],
    'accepted' => %w[connecting failed],
    'connecting' => %w[connected failed],
    'connected' => %w[holding ended failed],
    'holding' => %w[connected ended failed],
    'ended' => [],
    'failed' => [],
    'rejected' => [],
    'timeout' => []
  }.freeze

  attr_reader :conversation, :call_id

  def initialize(conversation:)
    @conversation = conversation
    @call_id = conversation.additional_attributes&.dig('call_id')
  end

  # Get current call state
  def current_state
    conversation.additional_attributes&.dig('call_status') || 'initiated'
  end

  # Check if transition is valid
  def can_transition_to?(new_state)
    return false unless VALID_STATES.include?(new_state)

    allowed_states = VALID_TRANSITIONS[current_state] || []
    allowed_states.include?(new_state)
  end

  # Transition to new state
  def transition_to!(new_state, reason: nil)
    unless can_transition_to?(new_state)
      Rails.logger.warn "[CallState] Invalid transition from #{current_state} to #{new_state}"
      return false
    end

    old_state = current_state

    # Update conversation
    attrs = conversation.additional_attributes || {}
    attrs['call_status'] = new_state
    attrs['call_status_updated_at'] = Time.current.to_i
    attrs['state_transition_reason'] = reason if reason.present?

    # Add timestamp for specific states
    case new_state
    when 'accepted'
      attrs['accepted_at'] = Time.current.to_i
    when 'connected'
      attrs['connected_at'] = Time.current.to_i
    when 'ended'
      attrs['ended_at'] = Time.current.to_i
      calculate_duration(attrs)
    end

    conversation.additional_attributes = attrs
    conversation.save!

    Rails.logger.info "[CallState] #{call_id}: #{old_state} → #{new_state}"

    # Trigger state-specific actions
    on_state_change(old_state, new_state)

    true
  end

  # Force state (bypass validation) - use with caution
  def force_state!(new_state, reason: nil)
    attrs = conversation.additional_attributes || {}
    attrs['call_status'] = new_state
    attrs['call_status_updated_at'] = Time.current.to_i
    attrs['forced_state'] = true
    attrs['state_transition_reason'] = reason if reason.present?

    conversation.additional_attributes = attrs
    conversation.save!

    Rails.logger.warn "[CallState] Forced state for #{call_id}: #{new_state} (#{reason})"
  end

  # Check if call is active
  def active?
    %w[ringing accepted connecting connected holding].include?(current_state)
  end

  # Check if call is ended
  def ended?
    %w[ended failed rejected timeout].include?(current_state)
  end

  # Get call duration in seconds (only if ended)
  def duration
    return nil unless ended?

    started_at = conversation.additional_attributes&.dig('connected_at')
    ended_at = conversation.additional_attributes&.dig('ended_at')

    return nil unless started_at && ended_at

    ended_at - started_at
  end

  # Get formatted duration (e.g., "2m 45s")
  def formatted_duration
    seconds = duration
    return nil unless seconds

    minutes = seconds / 60
    remaining_seconds = seconds % 60

    if minutes.positive?
      "#{minutes}m #{remaining_seconds}s"
    else
      "#{remaining_seconds}s"
    end
  end

  # Cleanup media session when call ends
  def cleanup_media_session
    return unless ended?

    session_info = conversation.additional_attributes&.dig('media_session')
    return unless session_info

    begin
      media_server = Whatsapp::Calling::MediaServerAdapter.new
      media_server.destroy_session(session_id: session_info['session_id'])

      Rails.logger.info "[CallState] Media session cleaned up for #{call_id}"
    rescue StandardError => e
      Rails.logger.error "[CallState] Failed to cleanup media session: #{e.message}"
    end
  end

  # Get call metadata
  def metadata
    {
      call_id: call_id,
      state: current_state,
      active: active?,
      ended: ended?,
      duration: duration,
      formatted_duration: formatted_duration,
      direction: conversation.additional_attributes&.dig('call_direction'),
      started_at: conversation.additional_attributes&.dig('connected_at'),
      ended_at: conversation.additional_attributes&.dig('ended_at')
    }
  end

  private

  def calculate_duration(attrs)
    started_at = attrs['connected_at']
    ended_at = attrs['ended_at']

    return unless started_at && ended_at

    duration_seconds = ended_at - started_at
    attrs['duration_seconds'] = duration_seconds
    attrs['duration'] = format_duration(duration_seconds)
  end

  def format_duration(seconds)
    minutes = seconds / 60
    remaining_seconds = seconds % 60

    if minutes.positive?
      "#{minutes}m #{remaining_seconds}s"
    else
      "#{remaining_seconds}s"
    end
  end

  def on_state_change(old_state, new_state)
    # Broadcast state change via ActionCable
    broadcast_state_change(old_state, new_state)

    # Cleanup media session on call end
    cleanup_media_session if ended?

    # Create activity message for significant state changes
    create_state_message(new_state) if should_log_state?(new_state)
  end

  def broadcast_state_change(old_state, new_state)
    data = {
      event: 'call_state_changed',
      call_id: call_id,
      conversation_id: conversation.display_id,
      old_state: old_state,
      new_state: new_state,
      metadata: metadata
    }

    ActionCable.server.broadcast(
      "account_#{conversation.account_id}",
      data
    )
  rescue StandardError => e
    Rails.logger.error "[CallState] Failed to broadcast state change: #{e.message}"
  end

  def should_log_state?(state)
    %w[accepted connected ended failed rejected].include?(state)
  end

  def create_state_message(state)
    content = case state
              when 'accepted' then '✅ Llamada aceptada'
              when 'connected' then '🔔 Llamada conectada'
              when 'ended' then "📞 Llamada finalizada (#{formatted_duration})"
              when 'failed' then '❌ Llamada fallida'
              when 'rejected' then '❌ Llamada rechazada'
              else return
              end

    conversation.messages.create!(
      account: conversation.account,
      inbox: conversation.inbox,
      message_type: :activity,
      content: content,
      content_attributes: {
        call_id: call_id,
        call_status: state
      }
    )
  rescue StandardError => e
    Rails.logger.error "[CallState] Failed to create state message: #{e.message}"
  end
end
