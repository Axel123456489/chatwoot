class AgentBotListener < BaseListener
  def conversation_updated(event)
    conversation = extract_conversation_and_account(event)[0]
    inbox = conversation.inbox
    agent_bots_for(inbox, conversation).each do |agent_bot|
      # Use new workflow integration if available
      if use_workflow_integration?(agent_bot)
        workflow_integration = agent_bot.workflow_integration
        WorkflowIntegrations::Executor.new(workflow_integration).handle_status_change(conversation, event)
      else
        integration_for(agent_bot).conversation_updated(conversation, event)
      end
    end
  end

  def conversation_created(event)
    conversation = extract_conversation_and_account(event)[0]
    inbox = conversation.inbox
    agent_bots_for(inbox, conversation).each do |agent_bot|
      integration_for(agent_bot).conversation_created(conversation, event)
    end
  end

  def conversation_resolved(event)
    conversation = extract_conversation_and_account(event)[0]
    inbox = conversation.inbox
    agent_bots_for(inbox, conversation).each do |agent_bot|
      integration_for(agent_bot).conversation_resolved(conversation, event)
    end
  end

  def conversation_opened(event)
    conversation = extract_conversation_and_account(event)[0]
    inbox = conversation.inbox
    agent_bots_for(inbox, conversation).each do |agent_bot|
      integration_for(agent_bot).conversation_opened(conversation, event)
    end
  end

  def message_created(event)
    message = extract_message_and_account(event)[0]
    inbox = message.inbox
    return unless message.webhook_sendable?

    agent_bots_for(inbox, message.conversation).each do |agent_bot|
      # Use new workflow integration if available
      if use_workflow_integration?(agent_bot)
        workflow_integration = agent_bot.workflow_integration
        WorkflowIntegrations::Executor.new(workflow_integration).handle_message(message)
      else
        integration_for(agent_bot).message_created(message, event)
      end
    end
  end

  def message_updated(event)
    message = extract_message_and_account(event)[0]
    inbox = message.inbox
    return unless message.webhook_sendable?

    agent_bots_for(inbox, message.conversation).each do |agent_bot|
      integration_for(agent_bot).message_updated(message, event)
    end
  end

  def webwidget_triggered(event)
    contact_inbox = event.data[:contact_inbox]
    inbox = contact_inbox.inbox
    agent_bots_for(inbox).each do |agent_bot|
      integration_for(agent_bot).webwidget_triggered(contact_inbox, event)
    end
  end

  private

  def agent_bots_for(inbox, conversation = nil)
    bots = []
    bots << conversation.assignee_agent_bot if conversation&.assignee_agent_bot.present?
    inbox_bot = active_inbox_agent_bot(inbox)
    bots << inbox_bot if inbox_bot.present?
    bots.compact.uniq
  end

  def active_inbox_agent_bot(inbox)
    return unless inbox.agent_bot_inbox&.active?

    inbox.agent_bot
  end

  def integration_for(agent_bot)
    if n8n_native_bot?(agent_bot)
      AgentBots::Integrations::N8nIntegration.new(agent_bot)
    else
      AgentBots::Integrations::WebhookIntegration.new(agent_bot)
    end
  end

  def n8n_native_bot?(agent_bot)
    flag = agent_bot&.bot_config&.dig('n8n_native')
    ActiveRecord::Type::Boolean.new.cast(flag) == true
  end

  def use_workflow_integration?(agent_bot)
    agent_bot.workflow_integration.present? && agent_bot.workflow_integration.enabled?
  end
end
