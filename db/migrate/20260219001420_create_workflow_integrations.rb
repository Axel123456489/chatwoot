# frozen_string_literal: true

class CreateWorkflowIntegrations < ActiveRecord::Migration[7.1]
  def change
    create_table :workflow_integrations do |t|
      t.string :type, null: false  # STI: WorkflowIntegrations::N8n, ::Make, etc
      t.references :agent_bot, null: false, foreign_key: true, index: true
      t.string :webhook_url, null: false
      t.jsonb :config, default: {}, null: false
      t.boolean :enabled, default: true, null: false
      t.string :status, default: 'active', null: false  # active, paused, error
      t.string :version, default: '1.0'
      t.jsonb :metadata, default: {}, null: false
      t.timestamps
    end

    add_index :workflow_integrations, :type
    add_index :workflow_integrations, :status
    add_index :workflow_integrations, :enabled
    add_index :workflow_integrations, [:agent_bot_id, :type], unique: true, name: 'index_workflow_integrations_unique_bot_type'
  end
end
