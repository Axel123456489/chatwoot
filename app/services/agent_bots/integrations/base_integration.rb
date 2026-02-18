class AgentBots::Integrations::BaseIntegration
  attr_reader :agent_bot

  def initialize(agent_bot)
    @agent_bot = agent_bot
  end

  def outgoing_url
    agent_bot&.outgoing_url
  end

  # Conversation events
  def conversation_updated(_conversation, _event); end
  def conversation_created(_conversation, _event); end
  def conversation_resolved(_conversation, _event); end
  def conversation_opened(_conversation, _event); end

  # Message events
  def message_created(_message, _event); end
  def message_updated(_message, _event); end

  # Webwidget
  def webwidget_triggered(_contact_inbox, _event); end
end
