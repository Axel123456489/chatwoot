# frozen_string_literal: true

# == Schema Information
#
# Table name: workflow_integrations
#
#  id          :bigint           not null, primary key
#  type        :string           not null (STI)
#  agent_bot_id :bigint          not null
#  webhook_url :string           not null
#  config      :jsonb            default({}), not null
#  enabled     :boolean          default(true), not null
#  status      :string           default('active'), not null
#  version     :string           default('1.0')
#  metadata    :jsonb            default({}), not null
#  created_at  :datetime         not null
#  updated_at  :datetime         not null
#
# Indexes
#
#  index_workflow_integrations_on_agent_bot_id           (agent_bot_id)
#  index_workflow_integrations_on_enabled                (enabled)
#  index_workflow_integrations_on_status                 (status)
#  index_workflow_integrations_on_type                   (type)
#  index_workflow_integrations_unique_bot_type           (agent_bot_id, type) UNIQUE
#

class WorkflowIntegration < ApplicationRecord
  belongs_to :agent_bot
  has_many :workflow_executions, dependent: :destroy
  
  validates :type, presence: true
  validates :webhook_url, presence: true, length: { maximum: Limits::URL_LENGTH_LIMIT }
  validates :webhook_url, format: { with: URI::DEFAULT_PARSER.make_regexp(%w[http https]) }, if: -> { webhook_url.present? }
  validates :status, inclusion: { in: %w[active paused error] }
  validates :agent_bot_id, uniqueness: { scope: :type, message: 'already has this type of workflow integration' }
  
  # Scopes
  scope :active, -> { where(enabled: true, status: 'active') }
  scope :by_type, ->(type) { where(type: type) }
  
  # STI - Each subclass must implement these methods
  def start_execution(conversation:, trigger_type:, payload:)
    raise NotImplementedError, "#{self.class} must implement #start_execution"
  end
  
  def forward_message(execution:, payload:)
    raise NotImplementedError, "#{self.class} must implement #forward_message"
  end
  
  def cancel_execution(execution:, reason: nil)
    raise NotImplementedError, "#{self.class} must implement #cancel_execution"
  end
  
  def should_start_for_trigger?(trigger_type)
    raise NotImplementedError, "#{self.class} must implement #should_start_for_trigger?"
  end
  
  # Shared helpers
  def active_execution_for(conversation)
    workflow_executions
      .where(conversation: conversation)
      .where(status: %w[pending running])
      .order(started_at: :desc)
      .first
  end
  
  def can_start_execution?(conversation)
    enabled? && active_status? && !active_execution_for(conversation)
  end
  
  def recent_executions(limit: 20)
    workflow_executions.order(started_at: :desc).limit(limit)
  end
  
  def success_rate(since: 7.days.ago)
    executions = workflow_executions.where('started_at >= ?', since)
    return 0 if executions.empty?
    
    completed = executions.where(status: 'completed').count
    total = executions.count
    (completed.to_f / total * 100).round(2)
  end
  
  # Status predicates
  def active_status?
    status == 'active'
  end
  
  def paused_status?
    status == 'paused'
  end
  
  def error_status?
    status == 'error'
  end
  
  # Config helpers - subclasses define their own accessors
  def config_value(key, default: nil)
    config.fetch(key.to_s, default)
  end
  
  def update_config(key, value)
    self.config = config.merge(key.to_s => value)
    save!
  end
  
  def merge_config(hash)
    self.config = config.merge(hash.stringify_keys)
    save!
  end
end
