# frozen_string_literal: true

# == Schema Information
#
# Table name: waha_sessions
#
#  id                    :bigint           not null, primary key
#  debug                 :boolean          default(FALSE)
#  ignore_broadcast      :boolean          default(TRUE)
#  ignore_channels       :boolean          default(TRUE)
#  ignore_groups         :boolean          default(FALSE)
#  ignore_status         :boolean          default(TRUE)
#  metadata              :jsonb
#  noweb_store_enabled   :boolean          default(TRUE)
#  noweb_store_full_sync :boolean          default(FALSE)
#  phone_number          :string
#  proxy_password        :string
#  proxy_server          :string
#  proxy_username        :string
#  qr_code               :text
#  qr_code_generated_at  :datetime
#  session_name          :string           not null
#  status                :string           default("pending"), not null
#  waha_data             :jsonb
#  created_at            :datetime         not null
#  updated_at            :datetime         not null
#  account_id            :bigint           not null
#  inbox_id              :bigint           not null
#
# Indexes
#
#  index_waha_sessions_on_account_id               (account_id)
#  index_waha_sessions_on_account_id_and_inbox_id  (account_id,inbox_id) UNIQUE
#  index_waha_sessions_on_inbox_id                 (inbox_id)
#  index_waha_sessions_on_session_name             (session_name) UNIQUE
#  index_waha_sessions_on_status                   (status)
#
# Foreign Keys
#
#  fk_rails_...  (account_id => accounts.id)
#  fk_rails_...  (inbox_id => inboxes.id)
#

class WahaSession < ApplicationRecord
  STATUSES = %w[pending starting scan_qr connecting connected failed stopped].freeze

  belongs_to :account
  belongs_to :inbox

  validates :session_name, presence: true, uniqueness: true
  validates :status, inclusion: { in: STATUSES }
  validates :proxy_server, format: { with: /\A[^:]+:\d+\z/, message: 'must be in format host:port' }, allow_blank: true

  before_validation :generate_session_name, on: :create
  before_destroy :delete_remote_waha_session
  after_commit :ensure_channel_webhook_configured, on: :create

  scope :active, -> { where(status: %w[scan_qr connecting connected]) }
  scope :connected, -> { where(status: 'connected') }

  delegate :channel, to: :inbox

  def api_channel
    channel if channel.is_a?(Channel::Api)
  end

  def waha_config
    account.waha_integration || {}
  end

  def waha_enabled?
    waha_config['enabled'] == true
  end

  def waha_base_url
    waha_config['base_url']
  end

  def waha_api_key
    waha_config['api_key']
  end

  def connected?
    status == 'connected'
  end

  def qr_code_expired?
    qr_code_generated_at.blank? || qr_code_generated_at < 90.seconds.ago
  end

  def inbox_identifier
    api_channel&.identifier
  end

  def inbox_webhook_url
    return nil if inbox_identifier.blank?

    base_url = ENV.fetch('FRONTEND_URL', 'http://localhost:3000')
    "#{base_url}/public/api/v1/inboxes/#{inbox_identifier}"
  end

  def waha_app_id
    "chatwoot_#{session_name}"
  end

  def waha_webhook_url
    return nil if waha_base_url.blank?

    "#{waha_base_url}/webhooks/chatwoot/#{session_name}/#{waha_app_id}"
  end

  # Map WAHA status to internal status
  def update_status_from_waha(waha_status)
    new_status = case waha_status&.upcase
                 when 'WORKING', 'CONNECTED'
                   'connected'
                 when 'SCAN_QR_CODE', 'SCAN_QR'
                   'scan_qr'
                 when 'STARTING'
                   'starting'
                 when 'STOPPED'
                   'stopped'
                 when 'FAILED'
                   'failed'
                 else
                   status
                 end

    update!(status: new_status) if new_status != status
  end

  def ensure_channel_webhook_configured
    webhook = waha_webhook_url
    channel = api_channel
    return if webhook.blank? || channel.blank? || channel.webhook_url == webhook

    channel.update(webhook_url: webhook)
  rescue StandardError => e
    Rails.logger.warn("[WAHA] Failed to set channel webhook: #{e.message}")
    true
  end

  private

  def generate_session_name
    return if session_name.present?

    self.session_name = "chatwoot_#{account_id}_#{SecureRandom.hex(4)}"
  end

  def delete_remote_waha_session
    return unless waha_enabled?

    Waha::SessionService.new(waha_session: self).delete_session
  rescue StandardError => e
    Rails.logger.warn("[WAHA] Failed to delete remote session during inbox cleanup: #{e.message}")
    true
  end
end
