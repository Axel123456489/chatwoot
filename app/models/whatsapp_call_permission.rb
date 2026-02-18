# == Schema Information
#
# Table name: whatsapp_call_permissions
#
#  id                :bigint           not null, primary key
#  permission_status :string           default("pending"), not null
#  granted_at        :datetime
#  expires_at        :datetime
#  remaining_calls   :integer          default(10), not null
#  metadata          :jsonb
#  created_at        :datetime         not null
#  updated_at        :datetime         not null
#  account_id        :bigint           not null
#  contact_id        :bigint           not null
#  phone_number_id   :string           not null
#

class WhatsappCallPermission < ApplicationRecord
  belongs_to :account
  belongs_to :contact
  belongs_to :inbox, optional: true
  belongs_to :requested_by_user, class_name: 'User', optional: true

  STATUSES = %w[pending requested granted revoked expired denied].freeze
  DAILY_CALL_LIMIT = 10

  alias_attribute :status, :permission_status

  validates :permission_status, inclusion: { in: STATUSES }
  validates :phone_number_id, presence: true
  validates :contact_id, uniqueness: { scope: [:account_id, :phone_number_id, :inbox_id] }

  scope :granted, -> { where(permission_status: 'granted') }
  scope :active, -> { granted.where('expires_at IS NULL OR expires_at > ?', Time.current) }

  # Class method with caching
  def self.can_call?(account:, contact:, phone_number_id:, inbox: nil)
    Rails.cache.fetch(
      cache_key_for(account: account, contact: contact, phone_number_id: phone_number_id, inbox: inbox),
      expires_in: 5.minutes
    ) do
      permission = find_by(account: account, contact: contact, phone_number_id: phone_number_id, inbox: inbox)
      permission&.granted? && !permission.expired? && permission.remaining_calls.positive?
    end
  end

  def self.cache_key_for(account:, contact:, phone_number_id:, inbox: nil)
    inbox_key = inbox.present? ? inbox.id : 'nil'
    "whatsapp_permission:#{account.id}:#{contact.id}:#{phone_number_id}:#{inbox_key}"
  end

  def self.clear_cache(account:, contact:, phone_number_id:, inbox: nil)
    Rails.cache.delete(cache_key_for(account: account, contact: contact, phone_number_id: phone_number_id, inbox: inbox))
  end

  def granted?
    permission_status == 'granted' && !expired?
  end

  def pending?
    permission_status == 'pending'
  end

  def requested?
    permission_status == 'requested'
  end

  def expired?
    expires_at.present? && expires_at < Time.current
  end

  def can_make_call?
    granted? && remaining_calls.positive?
  end

  def grant!
    update!(
      permission_status: 'granted',
      granted_at: Time.current,
      remaining_calls: DAILY_CALL_LIMIT
    )
    clear_cache
  end

  def revoke!
    update!(permission_status: 'revoked')
    clear_cache
  end

  def decrement_remaining_calls!
    decrement!(:remaining_calls)
    clear_cache
  end

  def reset_daily_limit!
    update!(remaining_calls: DAILY_CALL_LIMIT) if granted?
    clear_cache
  end

  after_destroy :clear_cache
  # Clear cache after updates
  after_save :clear_cache

  private

  def clear_cache
    self.class.clear_cache(account: account, contact: contact, phone_number_id: phone_number_id, inbox: inbox)
  end
end
