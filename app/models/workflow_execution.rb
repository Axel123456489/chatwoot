# frozen_string_literal: true

# == Schema Information
#
# Table name: workflow_executions
#
#  id                        :bigint           not null, primary key
#  workflow_integration_id   :bigint           not null
#  conversation_id           :bigint           not null
#  execution_id              :string           (external workflow ID)
#  webhook_url               :string
#  status                    :string           default('pending'), not null
#  trigger_type              :string           not null
#  started_at                :datetime
#  completed_at              :datetime
#  last_activity_at          :datetime
#  last_message_id           :bigint
#  metadata                  :jsonb            default({}), not null
#  error_message             :text
#  created_at                :datetime         not null
#  updated_at                :datetime         not null
#
# Indexes
#
#  index_workflow_executions_on_workflow_integration_id  (workflow_integration_id)
#  index_workflow_executions_on_conversation_id          (conversation_id)
#  index_workflow_executions_on_execution_id             (execution_id)
#  index_workflow_executions_on_status                   (status)
#  index_workflow_executions_on_trigger_type             (trigger_type)
#  index_workflow_executions_conversation_status         (conversation_id, status)
#  index_workflow_executions_unique_active_per_conversation (conversation_id) UNIQUE WHERE status IN ('pending', 'running')
#

class WorkflowExecution < ApplicationRecord
  belongs_to :workflow_integration
  belongs_to :conversation
  belongs_to :last_message, class_name: 'Message', optional: true
  
  validates :status, presence: true, inclusion: { 
    in: %w[pending running completed failed cancelled timeout] 
  }
  validates :trigger_type, presence: true, inclusion: {
    in: %w[new_conversation reopen manual_pending contact_pending webwidget manual]
  }
  
  # Scopes
  scope :active, -> { where(status: %w[pending running]) }
  scope :completed_states, -> { where(status: %w[completed failed cancelled timeout]) }
  scope :recent, -> { order(started_at: :desc) }
  scope :stale, ->(seconds = 3600) { 
    where('last_activity_at < ?', seconds.seconds.ago)
      .where(status: %w[pending running])
  }
  scope :by_trigger, ->(type) { where(trigger_type: type) }
  scope :successful, -> { where(status: 'completed') }
  scope :failed_states, -> { where(status: %w[failed timeout]) }
  
  # Callbacks
  after_create :log_creation
  after_update :log_status_change, if: :saved_change_to_status?
  
  # Lifecycle methods
  def start!(execution_id:, webhook_url: nil)
    update!(
      status: 'running',
      execution_id: execution_id,
      webhook_url: webhook_url || self.webhook_url,
      started_at: Time.current,
      last_activity_at: Time.current
    )
  end
  
  def mark_activity!(message_id: nil)
    attrs = { last_activity_at: Time.current }
    attrs[:last_message_id] = message_id if message_id
    update!(attrs)
  end
  
  def complete!(metadata: {})
    update!(
      status: 'completed',
      completed_at: Time.current,
      metadata: self.metadata.merge(metadata)
    )
  end
  
  def fail!(error_message:, metadata: {})
    update!(
      status: 'failed',
      error_message: error_message,
      completed_at: Time.current,
      metadata: self.metadata.merge(metadata)
    )
  end
  
  def cancel!(reason: nil)
    update!(
      status: 'cancelled',
      completed_at: Time.current,
      error_message: reason,
      metadata: metadata.merge(cancelled_at: Time.current.iso8601, cancellation_reason: reason)
    )
  end
  
  def mark_timeout!
    update!(
      status: 'timeout',
      completed_at: Time.current,
      error_message: 'Execution timed out due to inactivity',
      metadata: metadata.merge(timed_out_at: Time.current.iso8601)
    )
  end
  
  # Status predicates
  def active?
    pending_status? || running_status?
  end
  
  def pending_status?
    status == 'pending'
  end
  
  def running_status?
    status == 'running'
  end
  
  def completed_status?
    status == 'completed'
  end
  
  def failed_status?
    status == 'failed'
  end
  
  def cancelled_status?
    status == 'cancelled'
  end
  
  def timeout_status?
    status == 'timeout'
  end
  
  def terminal_state?
    %w[completed failed cancelled timeout].include?(status)
  end
  
  # Metrics
  def duration
    return nil unless started_at
    end_time = completed_at || Time.current
    (end_time - started_at).to_f
  end
  
  def duration_in_seconds
    duration&.round(2)
  end
  
  def duration_formatted
    return 'Not started' unless started_at
    return 'In progress' unless completed_at
    
    seconds = duration
    return "#{seconds.round(2)}s" if seconds < 60
    
    minutes = (seconds / 60).floor
    remaining_seconds = (seconds % 60).round
    "#{minutes}m #{remaining_seconds}s"
  end
  
  def stale?(threshold_seconds = 3600)
    return false unless active?
    return false unless last_activity_at
    
    last_activity_at < threshold_seconds.seconds.ago
  end
  
  # Data helpers
  def integration_type
    workflow_integration.type
  end
  
  def agent_bot
    workflow_integration.agent_bot
  end
  
  def push_event_data
    {
      id: id,
      execution_id: execution_id,
      status: status,
      trigger_type: trigger_type,
      started_at: started_at&.iso8601,
      completed_at: completed_at&.iso8601,
      duration: duration_in_seconds,
      conversation_id: conversation_id,
      integration_type: integration_type,
      error_message: error_message
    }
  end
  
  private
  
  def log_creation
    Rails.logger.info(
      "[WorkflowExecution] Created id=#{id} " \
      "conversation_id=#{conversation_id} " \
      "integration_type=#{integration_type} " \
      "trigger_type=#{trigger_type}"
    )
  end
  
  def log_status_change
    Rails.logger.info(
      "[WorkflowExecution] Status changed id=#{id} " \
      "#{status_before_last_save} → #{status} " \
      "conversation_id=#{conversation_id}"
    )
  end
end
