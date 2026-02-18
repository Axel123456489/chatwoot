# frozen_string_literal: true

# Presenter for WhatsApp call messages in the API
class Api::V1::Messages::WhatsappCallPresenter
  def initialize(message)
    @message = message
  end

  def as_json
    return {} unless @message.voice_call?

    {
      call_status: @message.call_status,
      call_duration: @message.call_duration,
      formatted_duration: @message.formatted_call_duration,
      call_direction: @message.call_direction,
      call_metadata: sanitized_metadata,
      has_recording: @message.has_recording?,
      status_icon: @message.call_status_icon,
      status_message: @message.call_status_message,
      is_successful: @message.call_successful?,
      is_failed: @message.call_failed?,
      is_meta_error: @message.call_meta_error?,
      timestamps: {
        initiated_at: @message.initiated_at,
        connected_at: @message.connected_at,
        ended_at: @message.ended_at
      }
    }
  end

  private

  def sanitized_metadata
    # Don't expose sensitive data like full meta_response
    metadata = @message.call_metadata.dup
    metadata.except('meta_response')
  end
end
