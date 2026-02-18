# frozen_string_literal: true

class Whatsapp::Calling::RecordingService
  include Whatsapp::Calling::Concerns::Loggable

  def initialize(call:)
    @call = call
    @channel = call&.inbox&.channel
  end

  # Stop recording for the given call. Returns a hash with
  # success flag, optional recording_url, duration, blob, and error.
  def stop
    return recording_disabled unless recording_enabled?

    # Placeholder implementation. In production this would call the media
    # server to finalize and fetch the recording. Keeping synchronous to
    # satisfy current expectations.
    { success: true, recording_url: nil, duration: nil, blob: nil }
  rescue StandardError => e
    log_error('Failed to stop recording', exception: e, call_id: @call&.call_id)
    { success: false, error: e.message }
  end

  alias stop_recording stop

  private

  def recording_enabled?
    @channel&.calling_config&.fetch('recording_enabled', false)
  end

  def recording_disabled
    { success: false, error: 'Recording disabled' }
  end
end
