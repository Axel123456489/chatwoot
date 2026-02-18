# frozen_string_literal: true

class Waha::SetupSessionJob < ApplicationJob
  queue_as :default

  def perform(waha_session_id)
    waha_session = WahaSession.find_by(id: waha_session_id)
    return unless waha_session

    service = Waha::SessionService.new(waha_session: waha_session)
    service.setup_session
  rescue StandardError => e
    Rails.logger.error("[WAHA] SetupSessionJob failed: #{e.message}")
    waha_session&.update(status: 'failed')
  end
end
