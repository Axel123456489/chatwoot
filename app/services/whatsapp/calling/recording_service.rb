# frozen_string_literal: true

class Whatsapp::Calling::RecordingService
  include Whatsapp::Calling::Concerns::Loggable

  # Delete recording files older than +days_old+ days from the local storage
  # directories used by both the conversations and calls controllers.
  def self.cleanup_old_recordings(days_old: 30)
    cutoff = days_old.days.ago
    dirs = [
      Rails.root.join('storage/whatsapp_call_recordings'),
      Rails.root.join('storage/call_recordings')
    ]

    deleted = 0
    dirs.each do |dir|
      next unless dir.exist?

      Dir.glob(dir.join('**', '*.{webm,mp4,ogg,wav}')).each do |path|
        next unless File.file?(path) && File.mtime(path) < cutoff

        File.delete(path)
        deleted += 1
      rescue StandardError => e
        Rails.logger.error "[RecordingService] Failed to delete #{path}: #{e.message}"
      end
    end

    Rails.logger.info "[RecordingService] Cleanup complete: #{deleted} file(s) older than #{days_old} days removed"
    deleted
  end

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
