# == Schema Information
#
# Table name: channel_whatsapp
#
#  id                             :bigint           not null, primary key
#  message_templates              :jsonb
#  message_templates_last_updated :datetime
#  phone_number                   :string           not null
#  provider                       :string           default("default")
#  provider_config                :jsonb
#  created_at                     :datetime         not null
#  updated_at                     :datetime         not null
#  account_id                     :integer          not null
#
# Indexes
#
#  index_channel_whatsapp_on_phone_number  (phone_number) UNIQUE
#

class Channel::Whatsapp < ApplicationRecord
  include Channelable
  include Reauthorizable

  self.table_name = 'channel_whatsapp'
  EDITABLE_ATTRS = [
    :phone_number,
    :provider,
    :calling_enabled,
    { provider_config: {} },
    { calling_config: {} }
  ].freeze

  # default at the moment is 360dialog lets change later.
  PROVIDERS = %w[default whatsapp_cloud].freeze
  before_validation :ensure_webhook_verify_token

  validates :provider, inclusion: { in: PROVIDERS }
  validates :phone_number, presence: true, uniqueness: true
  validate :validate_provider_config

  after_create :sync_templates
  before_destroy :teardown_webhooks
  after_commit :setup_webhooks, on: :create, if: :should_auto_setup_webhooks?

  def name
    'Whatsapp'
  end

  def provider_service
    if provider == 'whatsapp_cloud'
      Whatsapp::Providers::WhatsappCloudService.new(whatsapp_channel: self)
    else
      Whatsapp::Providers::Whatsapp360DialogService.new(whatsapp_channel: self)
    end
  end

  def mark_message_templates_updated
    # rubocop:disable Rails/SkipsModelValidations
    update_column(:message_templates_last_updated, Time.zone.now)
    # rubocop:enable Rails/SkipsModelValidations
  end

  delegate :send_message, to: :provider_service
  delegate :send_template, to: :provider_service
  delegate :send_reaction, to: :provider_service
  delegate :sync_templates, to: :provider_service
  delegate :media_url, to: :provider_service
  delegate :api_headers, to: :provider_service

  # Calling methods
  def calling_enabled?
    enabled_flag = calling_config&.dig('enabled') == true || calling_enabled == true

    provider == 'whatsapp_cloud' && enabled_flag && phone_number_id.present?
  end

  def phone_number_id
    provider_config['phone_number_id']
  end

  def whatsapp_business_account_id
    provider_config['business_account_id']
  end

  def api_key
    provider_config['api_key']
  end

  def media_server_config
    calling_config.presence || {}
  end

  def calling_credentials
    {
      phone_number_id: phone_number_id,
      business_account_id: whatsapp_business_account_id,
      api_key: api_key,
      webhook_verify_token: provider_config['webhook_verify_token']
    }
  end

  def call_webhook_url
    return if phone_number_id.blank?

    Rails.application.routes.url_helpers.whatsapp_calls_webhook_url(
      phone_number_id: phone_number_id
    )
  end

  def setup_webhooks
    perform_webhook_setup
  rescue StandardError => e
    Rails.logger.error "[WHATSAPP] Webhook setup failed: #{e.message}"
    prompt_reauthorization!
  end

  private

  def ensure_webhook_verify_token
    provider_config['webhook_verify_token'] ||= SecureRandom.hex(16) if provider == 'whatsapp_cloud'
  end

  def validate_provider_config
    return unless new_record? || will_save_change_to_provider_config? || will_save_change_to_provider?

    errors.add(:provider_config, 'Invalid Credentials') unless provider_service.validate_provider_config?
  end

  def perform_webhook_setup
    business_account_id = provider_config['business_account_id']
    api_key = provider_config['api_key']

    Whatsapp::WebhookSetupService.new(self, business_account_id, api_key).perform
  end

  def teardown_webhooks
    Whatsapp::WebhookTeardownService.new(self).perform
  end

  def should_auto_setup_webhooks?
    # Only auto-setup webhooks for whatsapp_cloud provider with manual setup
    # Embedded signup calls setup_webhooks explicitly in EmbeddedSignupService
    provider == 'whatsapp_cloud' && provider_config['source'] != 'embedded_signup'
  end
end
