# frozen_string_literal: true

# Background job to process call recordings
# NOTE: This job is no longer used. Recording upload is now done synchronously
# in RecordingService.stop_recording when the call ends.
class Whatsapp::Calling::ProcessRecordingsJob < ApplicationJob
  queue_as :low

  def perform
    # No-op: Recording processing is now synchronous
    Rails.logger.info '[Recording] ProcessRecordingsJob called but no longer needed (processing is synchronous)'
  end
end
