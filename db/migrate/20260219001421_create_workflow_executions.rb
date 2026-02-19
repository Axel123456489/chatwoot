# frozen_string_literal: true

class CreateWorkflowExecutions < ActiveRecord::Migration[7.1]
  def change
    create_table :workflow_executions do |t|
      t.references :workflow_integration, null: false, foreign_key: true, index: true
      t.references :conversation, null: false, foreign_key: true, index: true
      t.string :execution_id  # External workflow execution ID (e.g., n8n flow_id)
      t.string :webhook_url
      t.string :status, default: 'pending', null: false  # pending, running, completed, failed, cancelled, timeout
      t.string :trigger_type, null: false  # new_conversation, reopen, manual_pending, contact_pending, webwidget
      t.datetime :started_at
      t.datetime :completed_at
      t.datetime :last_activity_at
      t.bigint :last_message_id
      t.jsonb :metadata, default: {}, null: false
      t.text :error_message
      t.timestamps
    end

    add_index :workflow_executions, :execution_id
    add_index :workflow_executions, :status
    add_index :workflow_executions, :trigger_type
    add_index :workflow_executions, [:conversation_id, :status], name: 'index_workflow_executions_conversation_status'
    add_index :workflow_executions, :last_activity_at
    add_index :workflow_executions, :started_at
    
    # Ensure only one active execution per conversation
    add_index :workflow_executions, :conversation_id,
              unique: true,
              where: "status IN ('pending', 'running')",
              name: 'index_workflow_executions_unique_active_per_conversation'
              
    add_foreign_key :workflow_executions, :messages, column: :last_message_id
  end
end
