# == Schema Information
#
# Table name: agent_bots
#
#  id           :bigint           not null, primary key
#  bot_config   :jsonb
#  bot_type     :integer          default("webhook")
#  description  :string
#  name         :string
#  outgoing_url :string
#  created_at   :datetime         not null
#  updated_at   :datetime         not null
#  account_id   :bigint
#
# Indexes
#
#  index_agent_bots_on_account_id  (account_id)
#

class AgentBot < ApplicationRecord
  include AccessTokenable
  include Avatarable

  scope :accessible_to, lambda { |account|
    account_id = account&.id
    where(account_id: [nil, account_id])
  }

  has_many :agent_bot_inboxes, dependent: :destroy_async
  has_many :inboxes, through: :agent_bot_inboxes
  has_many :messages, as: :sender, dependent: :nullify
  has_many :assigned_conversations, class_name: 'Conversation',
                                    foreign_key: :assignee_agent_bot_id,
                                    dependent: :nullify,
                                    inverse_of: :assignee_agent_bot
  belongs_to :account, optional: true
  enum bot_type: { webhook: 0 }

  validates :outgoing_url, length: { maximum: Limits::URL_LENGTH_LIMIT }

  def available_name
    name
  end

  def push_event_data(inbox = nil)
    {
      id: id,
      name: name,
      avatar_url: avatar_url || inbox&.avatar_url,
      type: 'agent_bot'
    }
  end

  def webhook_data
    {
      id: id,
      name: name,
      type: 'agent_bot'
    }
  end

  def system_bot?
    account.nil?
  end

  before_validation :normalize_bot_config_flags

  private

  def normalize_bot_config_flags
    return unless bot_config.is_a?(Hash)

    cfg = bot_config.dup

    boolean_keys = %w[
      n8n_native
      n8n_start_on_message
      n8n_start_on_conversation_created
      n8n_start_on_manual_pending
      n8n_restart_on_reopen
      n8n_start_on_reopen
    ]
    boolean_keys.each do |key|
      next unless cfg.key?(key)

      cfg[key] = ActiveRecord::Type::Boolean.new.cast(cfg[key])
    end

    cfg['n8n_triggers_version'] = normalize_trigger_version(cfg['n8n_triggers_version'])

    cfg.delete('n8n_allowed_statuses')

    self.bot_config = cfg
  end

  def normalize_trigger_version(raw_version)
    version = raw_version.to_i
    version.positive? ? version : 2
  end
end
