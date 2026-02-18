class N8nFlow < ApplicationRecord
  belongs_to :conversation

  delegate :account_id, to: :conversation

  validates :conversation_id, presence: true
  validates :flow_webhook_url, length: { maximum: Limits::URL_LENGTH_LIMIT }, allow_blank: true

  def active?
    flow_id.present?
  end
end
