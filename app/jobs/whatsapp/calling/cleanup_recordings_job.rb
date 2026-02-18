# frozen_string_literal: true

# Background job to cleanup old call recordings
class Whatsapp::Calling::CleanupRecordingsJob < ApplicationJob
  queue_as :low

  def perform(days_old = 30)
    Whatsapp::Calling::RecordingService.cleanup_old_recordings(days_old: days_old)
  end
end
