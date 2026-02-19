# == Schema Information
#
# Table name: n8n_flows
#
#  id                :bigint           not null, primary key
#  flow_webhook_url  :string
#  last_triggered_at :datetime
#  created_at        :datetime         not null
#  updated_at        :datetime         not null
#  conversation_id   :bigint           not null
#  flow_id           :string
#  last_message_id   :bigint
#
# Indexes
#
#  index_n8n_flows_on_conversation_id  (conversation_id) UNIQUE
#
# Foreign Keys
#
#  fk_rails_...  (conversation_id => conversations.id)
#
class N8nFlow < ApplicationRecord
  belongs_to :conversation

  delegate :account_id, to: :conversation

  validates :conversation_id, presence: true
  validates :flow_webhook_url, length: { maximum: Limits::URL_LENGTH_LIMIT }, allow_blank: true

  def active?
    flow_id.present?
  end
end
