# frozen_string_literal: true

# Concern for handling WhatsApp call messages
# Call messages are special message types that track call lifecycle without sending actual text
module Message::WhatsappCallMessage # rubocop:disable Metrics/ModuleLength
  extend ActiveSupport::Concern

  CALL_STATUS_ALIASES = {
    call_initiated: :initiated,
    call_connected: :connected,
    call_completed: :completed,
    call_rejected: :rejected,
    call_missed: :missed,
    call_cancelled: :cancelled,
    call_busy: :busy,
    call_no_connection: :no_connection,
    call_failed: :failed,
    call_error_unauthorized: :unauthorized,
    call_error_no_balance: :no_balance,
    call_error_not_enabled: :not_enabled,
    call_error_rate_limit: :rate_limit,
    call_error_invalid: :invalid,
    call_error_recipient_not_approved: :other_meta_error
  }.freeze

  included do
    # Call status enum - represents the lifecycle of a call
    enum call_status: {
      initiated: 0,
      connected: 1,
      completed: 2,
      rejected: 3,
      missed: 4,
      cancelled: 5,
      busy: 6,
      no_connection: 7,
      failed: 8,
      unauthorized: 9,
      no_balance: 10,
      not_enabled: 11,
      rate_limit: 12,
      invalid: 13,
      other_meta_error: 14
    }, _prefix: true

    # Validations
    validates :call_duration, numericality: { greater_than_or_equal_to: 0 }, allow_nil: true

    # Scopes
    scope :call_messages, -> { where(content_type: :voice_call) }
    scope :completed_calls, -> { call_messages.where(call_status: :completed) }
    scope :failed_calls, -> { call_messages.where(call_status: call_failed_statuses) }
    scope :successful_calls, -> { call_messages.where(call_status: call_successful_statuses) }

    # Store additional call metadata
    store_accessor :call_metadata,
                   :call_id,              # WhatsApp call_id
                   :call_direction,       # 'inbound' or 'outbound'
                   :whatsapp_call_sid,    # WhatsApp call SID
                   :initiated_at,         # When call was initiated (timestamp)
                   :connected_at,         # When call was connected (timestamp)
                   :ended_at,             # When call ended (timestamp)
                   :recording_url,        # URL to call recording
                   :recording_duration,   # Duration of recording in seconds
                   :error_code,           # Meta API error code
                   :error_message,        # Meta API error message
                   :meta_response         # Full Meta API response for debugging

    CALL_STATUS_ALIASES.each_key do |alias_key|
      define_method("call_status_#{alias_key}?") do
        call_status == CALL_STATUS_ALIASES[alias_key].to_s
      end
    end
  end

  class_methods do
    # Get statuses that represent successful calls
    def call_successful_statuses
      %w[initiated connected completed]
    end

    # Get statuses that represent failed/unsuccessful calls
    def call_failed_statuses
      %w[rejected missed cancelled busy no_connection failed]
    end

    # Get statuses that represent Meta API errors
    def call_meta_error_statuses
      %w[
        unauthorized no_balance not_enabled rate_limit invalid other_meta_error
      ]
    end

    def meta_error_to_call_status(error_code, error_message = nil)
      Message::WhatsappCallMessage.meta_error_to_call_status_value(error_code, error_message)
    end

    def call_statuses
      base_statuses = super()
      alias_statuses = CALL_STATUS_ALIASES.transform_values { |new_key| base_statuses[new_key.to_s] }
                                          .transform_keys(&:to_s)
      base_statuses.merge(alias_statuses)
    end
  end

  # Instance methods

  def voice_call?
    content_type == 'voice_call'
  end

  def call_status=(value)
    normalized = normalize_call_status_value(value)
    super(normalized)
  end

  # Provide call information for push events and API responses
  def call_info_data
    return nil unless voice_call?

    {
      call_status: call_status,
      call_duration: call_duration,
      formatted_duration: formatted_call_duration,
      call_direction: call_direction,
      has_recording: has_recording?,
      status_icon: call_status_icon,
      status_message: call_status_message,
      is_successful: call_successful?,
      is_failed: call_failed?,
      is_meta_error: call_meta_error?,
      timestamps: {
        initiated_at: initiated_at,
        connected_at: connected_at,
        ended_at: ended_at
      }
    }
  end

  def call_in_progress?
    voice_call? && (call_status_initiated? || call_status_connected?)
  end

  def call_ended?
    voice_call? && !call_in_progress?
  end

  def call_successful?
    voice_call? && call_status.in?(self.class.call_successful_statuses)
  end

  def call_failed?
    voice_call? && call_status.in?(self.class.call_failed_statuses)
  end

  def call_meta_error?
    voice_call? && call_status.in?(self.class.call_meta_error_statuses)
  end

  def has_recording?
    voice_call? && recording_url.present?
  end

  def formatted_call_duration
    return nil unless call_duration.present? && call_duration.positive?

    minutes = call_duration / 60
    seconds = call_duration % 60
    parts = []
    parts << "#{minutes}m" if minutes.positive?
    parts << "#{seconds}s"
    parts.join(' ')
  end

  def call_status_icon
    case call_status
    when 'initiated'
      'phone'
    when 'connected'
      'phone-call'
    when 'completed'
      'phone-call'
    when 'rejected'
      'phone-missed'
    when 'missed'
      'phone-missed'
    when 'cancelled'
      'phone-off'
    when 'busy'
      'phone-outgoing'
    when 'no_connection'
      'wifi-off'
    when 'failed', 'unauthorized', 'other_meta_error'
      'alert-circle'
    when 'invalid'
      'alert-triangle'
    when 'no_balance'
      'credit-card'
    when 'rate_limit'
      'clock'
    when 'not_enabled'
      'x-circle'
    else
      'alert-circle'
    end
  end

  def call_status_message
    case call_status
    when 'initiated'
      'Call initiated'
    when 'connected'
      'Call connected'
    when 'completed'
      duration_text = formatted_call_duration
      duration_text.present? ? "Call completed (#{duration_text})" : 'Call completed'
    when 'rejected'
      'Call rejected'
    when 'missed'
      'Call missed'
    when 'cancelled'
      'Call cancelled'
    when 'busy'
      'User busy'
    when 'no_connection'
      'Connection failed'
    when 'failed'
      'Call failed'
    when 'unauthorized'
      'Call failed: Not authorized'
    when 'no_balance'
      'Call failed: Insufficient balance'
    when 'not_enabled'
      'Call failed: Calling not enabled'
    when 'rate_limit'
      'Call failed: Rate limit exceeded'
    when 'invalid'
      'Call failed: Invalid parameters'
    when 'other_meta_error'
      'Call failed: Meta API error'
    else
      'Unknown call status'
    end
  end

  # Map Meta API error codes to call statuses
  def self.meta_error_to_call_status_value(error_code, error_message = nil)
    case error_code.to_s
    when 'PERMISSION_DENIED', '100', '190'
      'unauthorized'
    when 'INSUFFICIENT_BALANCE'
      'no_balance'
    when 'CALLING_NOT_ENABLED'
      'not_enabled'
    when 'RATE_LIMIT_HIT', '2', '4', '17'
      'rate_limit'
    when 'INVALID_PARAMETER', '131056', '131_056'
      'invalid'
    else
      if error_message.present?
        msg_lower = error_message.downcase
        return 'unauthorized' if msg_lower.include?('permission') || msg_lower.include?('unauthorized')
        return 'no_balance' if msg_lower.include?('balance') || msg_lower.include?('credit')
        return 'not_enabled' if msg_lower.include?('not enabled') || msg_lower.include?('disabled')
        return 'invalid' if msg_lower.include?('invalid') || msg_lower.include?('parameter')
      end

      'other_meta_error'
    end
  end

  private

  def normalize_call_status_value(value)
    return value if value.blank?

    value_str = value.to_s
    return CALL_STATUS_ALIASES[value_str.to_sym] if CALL_STATUS_ALIASES.key?(value_str.to_sym)

    value
  end
end
