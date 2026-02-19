class Api::V1::Integrations::WorkflowsController < ApplicationController
  protect_from_forgery with: :null_session
  before_action :set_conversation, only: [:executions, :cancel_execution, :switch_execution]
  before_action :set_workflow_integration, only: [:executions, :cancel_execution, :switch_execution]

  # GET /api/v1/integrations/workflows/executions
  # Params: conversation_id
  # Returns execution history for a conversation
  def executions
    @executions = @workflow_integration.workflow_executions
                                       .where(conversation_id: @conversation.id)
                                       .order(created_at: :desc)
                                       .limit(20)

    render json: { 
      executions: @executions.as_json(
        only: [:id, :execution_id, :status, :trigger_type, :created_at, :updated_at, :last_activity_at],
        methods: [:duration]
      )
    }
  end

  # POST /api/v1/integrations/workflows/cancel_execution
  # Params: conversation_id
  # Cancels the active execution for a conversation
  def cancel_execution
    execution = @workflow_integration.active_execution_for(@conversation)
    
    if execution.nil?
      return render json: { error: 'No active execution found' }, status: :not_found
    end

    execution.cancel!
    
    # También cancelar en n8n si tiene execution_id
    if execution.execution_id.present? && @workflow_integration.is_a?(WorkflowIntegrations::N8n)
      cancel_url = @workflow_integration.send(:build_cancel_url, execution)
      WorkflowIntegrations::WebhookPoster.post(cancel_url, {}) rescue nil if cancel_url
    end

    render json: { 
      message: 'Execution cancelled',
      execution: execution.as_json(only: [:id, :execution_id, :status])
    }
  rescue StandardError => e
    Rails.logger.error("[Workflows][API] cancel_execution error conversation_id=#{@conversation.id} error=#{e.class} #{e.message}")
    render json: { error: e.message }, status: :internal_server_error
  end

  # POST /api/v1/integrations/workflows/switch_execution
  # Params: conversation_id, execution_id, webhook_url (optional)
  # Switches to a different workflow execution (handoff between flows)
  def switch_execution
    new_execution_id = params[:execution_id]
    new_webhook_url = params[:webhook_url]

    return render json: { error: 'execution_id missing' }, status: :bad_request if new_execution_id.blank?

    # Cancel existing execution
    current_execution = @workflow_integration.active_execution_for(@conversation)
    current_execution&.cancel!

    # Create new execution
    execution = @workflow_integration.workflow_executions.create!(
      conversation: @conversation,
      execution_id: new_execution_id,
      status: :running,
      trigger_type: :manual_switch,
      metadata: { switched_from: current_execution&.execution_id }
    )

    # If webhook_url provided, update the integration's URL temporarily
    if new_webhook_url.present? && @workflow_integration.is_a?(WorkflowIntegrations::N8n)
      # Store original URL in execution metadata for potential rollback
      execution.update!(
        metadata: execution.metadata.merge(original_webhook_url: @workflow_integration.webhook_url)
      )
    end

    render json: { 
      message: 'Execution switched',
      conversation_id: @conversation.id,
      execution_id: execution.execution_id,
      status: execution.status
    }
  rescue StandardError => e
    Rails.logger.error("[Workflows][API] switch_execution error conversation_id=#{@conversation.id} error=#{e.class} #{e.message}")
    render json: { error: e.message }, status: :internal_server_error
  end

  private

  def set_conversation
    conversation_id = params[:conversation_id]
    return render json: { error: 'conversation_id missing' }, status: :bad_request if conversation_id.blank?

    @conversation = Conversation.find_by(id: conversation_id)
    return render json: { error: 'conversation not found' }, status: :not_found unless @conversation
  end

  def set_workflow_integration
    # Find workflow integration through the conversation's assigned agent bot
    agent_bot = @conversation.assignee_agent_bot || @conversation.inbox.agent_bot
    
    unless agent_bot&.workflow_integration
      return render json: { error: 'No workflow integration found for this conversation' }, status: :not_found
    end

    @workflow_integration = agent_bot.workflow_integration
  end
end
