# frozen_string_literal: true

class Waha::SyncSessionStatusJob < ApplicationJob
  queue_as :low

  def perform
    WahaSession.active.find_each do |session|
      sync_session(session)
    rescue StandardError => e
      Rails.logger.error("[WAHA] Failed to sync session #{session.id}: #{e.message}")
    end
  end

  private

  def sync_session(session)
    return unless session.waha_enabled?

    service = Waha::SessionService.new(waha_session: session)
    service.get_status
  end
end
