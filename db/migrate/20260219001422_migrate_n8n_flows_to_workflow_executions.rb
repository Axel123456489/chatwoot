class MigrateN8nFlowsToWorkflowExecutions < ActiveRecord::Migration[7.1]
  def up
    # Primero, crear WorkflowIntegrations para bots existentes con n8n
    AgentBot.where("bot_config->>'n8n_native' = 'true'").find_each do |bot|
      webhook_url = bot.bot_config.dig('n8n_webhook_url')
      next if webhook_url.blank?

      WorkflowIntegrations::N8n.create!(
        agent_bot: bot,
        webhook_url: webhook_url,
        status: :active,
        config: {
          on_conversation_opened: bot.bot_config.dig('n8n_on_conversation_opened') || false,
          on_conversation_pending: bot.bot_config.dig('n8n_on_conversation_pending') || false,  
          on_message_created: bot.bot_config.dig('n8n_on_message_created') || false,
          on_assignee_changed: bot.bot_config.dig('n8n_on_assignee_changed') || false
        }
      )
      Rails.logger.info("Migrated AgentBot ##{bot.id} to WorkflowIntegration")
    end

    # Luego, migrar datos de n8n_flows a workflow_executions
    # Buscar por assignee_agent_bot_id en la conversación o por agent_bot del inbox
    execute <<-SQL
      INSERT INTO workflow_executions (
        workflow_integration_id,
        conversation_id,
        execution_id,
        webhook_url,
        status,
        trigger_type,
        metadata,
        last_message_id,
        started_at,
        last_activity_at,
        created_at,
        updated_at
      )
      SELECT DISTINCT
        wi.id as workflow_integration_id,
        nf.conversation_id,
        nf.flow_id as execution_id,
        COALESCE(nf.flow_webhook_url, wi.webhook_url) as webhook_url,
        CASE 
          WHEN nf.flow_id IS NOT NULL THEN 'running'
          ELSE 'pending'
        END as status,
        'conversation_pending' as trigger_type,
        '{}'::jsonb as metadata,
        nf.last_message_id,
        COALESCE(nf.last_triggered_at, nf.created_at) as started_at,
        COALESCE(nf.last_triggered_at, nf.updated_at) as last_activity_at,
        nf.created_at,
        nf.updated_at
      FROM n8n_flows nf
      INNER JOIN conversations c ON c.id = nf.conversation_id
      LEFT JOIN agent_bot_inboxes abi ON abi.inbox_id = c.inbox_id
      LEFT JOIN workflow_integrations wi ON (
        wi.agent_bot_id = c.assignee_agent_bot_id 
        OR wi.agent_bot_id = abi.agent_bot_id
      )
      WHERE wi.type = 'WorkflowIntegrations::N8n'
        AND nf.flow_id IS NOT NULL
        AND wi.id IS NOT NULL
      ON CONFLICT DO NOTHING
    SQL

    Rails.logger.info("Migrated #{N8nFlow.count} n8n_flows to workflow_executions")
  end

  def down
    # Eliminar workflow_executions migrados
    WorkflowExecution.where("created_at >= ?", Time.current - 1.hour).delete_all
    
    # Eliminar workflow_integrations creados
    WorkflowIntegrations::N8n.where("created_at >= ?", Time.current - 1.hour).delete_all
  end
end
