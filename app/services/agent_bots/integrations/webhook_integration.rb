class AgentBots::Integrations::WebhookIntegration < AgentBots::Integrations::BaseIntegration
  def conversation_updated(conversation, event)
    payload = conversation.webhook_data.merge(event: event_name(event))
    perform_webhook(payload)
  end

  def conversation_created(conversation, event)
    payload = conversation.webhook_data.merge(event: event_name(event))
    perform_webhook(payload)
  end

  def conversation_resolved(conversation, event)
    payload = conversation.webhook_data.merge(event: event_name(event))
    perform_webhook(payload)
  end

  def conversation_opened(conversation, event)
    payload = conversation.webhook_data.merge(event: event_name(event))
    perform_webhook(payload)
  end

  def message_created(message, event)
    payload = message.webhook_data.merge(event: event_name(event))
    perform_webhook(payload)
  end

  def message_updated(message, event)
    payload = message.webhook_data.merge(event: event_name(event))
    perform_webhook(payload)
  end

  def webwidget_triggered(contact_inbox, event)
    payload = contact_inbox.webhook_data.merge(event: 'webwidget_triggered')
    payload[:event_info] = event.data[:event_info]
    perform_webhook(payload)
  end

  private

  def event_name(event)
    raw = (event.respond_to?(:name) && event.name) || event.try(:event) || event.try(:type) || infer_event_from_callstack
    raw.to_s.tr('.', '_')
  end

  def infer_event_from_callstack
    caller_locations(2, 1)[0].label
  end

  def perform_webhook(payload)
    return if outgoing_url.blank?

    AgentBots::WebhookJob.perform_later(outgoing_url, payload)
  end
end
