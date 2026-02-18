# frozen_string_literal: true

# N8n native integration for Chatwoot
# Handles conversation and message events to orchestrate n8n workflows
#
# IMPORTANT: All flow starts happen via message_created event (incoming messages only)
# conversation_updated only handles:
#   - Manual pending changes by agents (no incoming message trigger)
#   - Exit from pending status (cleanup)
#
# Configuration flags (bot_config):
#   - n8n_native: Enable n8n integration
#   - n8n_start_on_message: Start flow on first incoming message of NEW conversation (default: true)
#   - n8n_start_on_manual_pending: Start flow when agent manually sets pending FROM ANY STATUS (default: true)
#   - n8n_start_on_reopen: Start flow when customer message reopens resolved conversation (default: true)
#                          If disabled, conversation goes to 'open' instead of 'pending'
#
class AgentBots::Integrations::N8nIntegration < AgentBots::Integrations::BaseIntegration
  # ===========================================
  # Public Event Handlers
  # ===========================================

  # Only handles:
  # 1. Manual pending changes by agents (User actor)
  # 2. Exit from pending (cleanup)
  # Does NOT handle message-triggered status changes (those go through message_created)
  def conversation_updated(conversation, event)
    log_debug('conversation_updated:start', conversation_id: conversation.id, status: conversation.status, bot_id: agent_bot&.id)
    reload_conversation_state!(conversation)
    return handle_exit_from_pending(conversation) if status_change_from_pending?(event)

    unless manual_pending_change?(event)
      log_debug('conversation_updated:skip_non_manual', conversation_id: conversation.id)
      return
    end
    unless start_on_manual_pending?
      log_debug('conversation_updated:disabled_manual_pending', conversation_id: conversation.id)
      return
    end

    start_flow_for_conversation(conversation, event)
  end

  def conversation_created(_conversation, _event)
    # Flow start for new conversations is handled by message_created
    # This ensures we always use message.created event type
  end

  def conversation_resolved(_conversation, _event); end

  def conversation_opened(_conversation, _event); end

  # Main entry point for all incoming message flows
  # Handles: new conversations, reopened conversations, forwarding to active flows
  def message_created(message, event)
    return unless processable_message?(message)

    conversation = message.conversation
    reload_conversation_state!(conversation)

    if active_flow?(conversation)
      forward_message_to_flow(conversation, message, event)
    else
      maybe_start_flow_from_message(conversation, message, event)
    end
  end

  def message_updated(_message, _event); end

  def webwidget_triggered(contact_inbox, event)
    return if outgoing_url.blank?

    payload = webwidget_payload(contact_inbox, event)
    touch_last_triggered(contact_inbox)
    AgentBots::WebhookJob.perform_later(outgoing_url, payload)
  rescue StandardError => e
    log_error('webwidget_triggered', e, contact_inbox_id: contact_inbox.id)
  end

  private

  # ===========================================
  # Flow Control Logic
  # ===========================================

  # Check if this is a MANUAL pending change (by User/Agent, not by message/contact)
  def manual_pending_change?(event)
    unless status_change_to_pending?(event)
      log_debug('manual_pending_change:no_status_change', status_change: status_change_pair(event))
      return false
    end

    actor = get_actor(event) || Current.user
    result = case actor
             when User
               true
             when Contact
               # Allow contact-triggered pending when explicitly enabled
               start_on_contact_pending?
             when AgentBot
               # Bot-triggered status changes (from ensure_pending_status!) should go through message_created
               false
             when nil
               # If both performed_by and Current.user are nil, likely an automatic change
               # Reject to avoid double execution with message_created
               false
             else
               false
             end
    log_debug('manual_pending_change:actor_check', actor_class: actor&.class&.name, result: result)
    result
  end

  def start_flow_for_conversation(conversation, event)
    unless conversation.pending?
      log_debug('start_flow_for_conversation:not_pending', conversation_id: conversation.id, status: conversation.status)
      return
    end

    orchestrator = orchestrator_for(conversation)
    reset_stale_flow!(orchestrator, conversation)

    return if outgoing_url.blank?

    payload = conversation_payload(conversation, event)
    log_debug('start_flow_for_conversation:trigger', conversation_id: conversation.id, event: event_name(event))
    orchestrator.start_or_update_with_full_url(payload: payload, start_url: outgoing_url)
  rescue StandardError => e
    log_error('start_flow', e, conversation_id: conversation.id)
  end

  def forward_message_to_flow(conversation, message, event)
    return unless conversation.pending?

    payload = message_payload(message, event)
    orchestrator_for(conversation).forward_message(payload: payload)
  end

  def maybe_start_flow_from_message(conversation, message, event)
    return if flow_recently_started?(conversation)

    unless should_start_flow_for_message?(conversation, message, event)
      ensure_open_status!(conversation)
      return
    end

    ensure_pending_status!(conversation)
    return unless conversation.reload.pending?
    return if outgoing_url.blank?

    payload = message_payload(message, event)
    log_debug('maybe_start_flow_from_message:trigger', conversation_id: conversation.id, message_id: message.id)
    orchestrator_for(conversation).start_or_update_with_full_url(payload: payload, start_url: outgoing_url)
  rescue StandardError => e
    log_error('message_start_flow', e, conversation_id: conversation.id)
  end

  def handle_exit_from_pending(conversation)
    clear_bot_assignment(conversation)
  end

  def reset_stale_flow!(orchestrator, conversation)
    return unless conversation.n8n_flow&.active?

    orchestrator.reset_flow
  end

  # ===========================================
  # Trigger Decision Helpers
  # ===========================================

  # Determines if we should start a flow for this incoming message
  def should_start_flow_for_message?(conversation, message, event)
    if new_conversation?(conversation, message)
      # New conversation - check start_on_message
      result = start_on_message?
      log_debug('should_start_flow:new_conversation', result: result)
      result
    elsif message_reopened_conversation?(event)
      # Message reopened from resolved - check start_on_reopen
      result = start_on_reopen?
      log_debug('should_start_flow:reopened_by_message', result: result, reopened: true)
      result
    else
      # Conversation exists but wasn't reopened (maybe from open/snoozed)
      # Don't auto-start flow in this case
      log_debug('should_start_flow:existing_open',
                status: conversation.status,
                reopened: false)
      false
    end
  end

  # Check if this is effectively a new conversation (first incoming message)
  def new_conversation?(conversation, message)
    !conversation.messages.incoming.where.not(id: message.id).exists?
  end

  # ===========================================
  # Status Change Detection
  # ===========================================

  def status_change_to_pending?(event)
    pair = status_change_pair(event)
    result = pair&.last == 'pending'
    log_debug('status_change_to_pending', pair: pair, result: result)
    result
  end

  def status_change_from_pending?(event)
    pair = status_change_pair(event)
    pair.present? && pair.first == 'pending' && pair.last != 'pending'
  end

  def status_change_pair(event)
    data = event.respond_to?(:data) ? event.data : {}
    return unless data.is_a?(Hash)

    changed = data[:changed_attributes] || data['changed_attributes'] || {}
    raw = changed['status'] || changed[:status]
    return if raw.blank?

    previous, current = extract_status_values(raw)
    pair = [previous, current].map { |v| v&.to_s }
    pair.compact.empty? ? nil : pair
  end

  def extract_status_values(raw)
    case raw
    when Array
      [raw.first, raw.last]
    when Hash
      [raw[:previous_value] || raw['previous_value'],
       raw[:current_value] || raw['current_value']]
    else
      [nil, raw]
    end
  end

  def get_actor(event)
    return nil unless event.respond_to?(:data)

    event.data[:performed_by] || event.data['performed_by']
  end

  # ===========================================
  # Message & Conversation Helpers
  # ===========================================

  def processable_message?(message)
    message.incoming? && !message.private? && message.sender.is_a?(Contact)
  end

  # Check if the message reopened the conversation from resolved status
  # This information is passed directly in the event data
  def message_reopened_conversation?(event)
    return false unless event.respond_to?(:data)

    event.data[:reopened_conversation] == true || event.data['reopened_conversation'] == true
  end

  # Check if conversation was recently reopened from resolved status
  # This is a fallback method, prefer using message_reopened_conversation? when available
  def conversation_was_reopened?(conversation)
    # First check if there was an actual status change in this request
    if conversation.previous_changes['status'].present?
      previous_status = conversation.previous_changes['status'].first
      current_status = conversation.previous_changes['status'].last

      # Only consider it reopened if it went from resolved to open/pending
      return previous_status == 'resolved' && %w[open pending].include?(current_status)
    end

    # Fallback: If conversation is currently pending/open and was recently updated (within 2 seconds)
    # this likely means it was just reopened by an incoming message
    # This handles the case where previous_changes is empty because we're in a separate job
    return false unless %w[pending open].include?(conversation.status)
    return false unless conversation.updated_at > 2.seconds.ago

    # Check if there's a recent status change in the database
    # by looking at the last message timestamp vs conversation updated_at
    last_message = conversation.messages.incoming.order(:created_at).last
    return false if last_message.blank?

    # If the message and conversation update happened at nearly the same time,
    # and conversation is now pending/open, it was likely reopened
    time_diff = (conversation.updated_at - last_message.created_at).abs
    time_diff < 2.seconds
  end

  def active_flow?(conversation)
    conversation.n8n_flow&.active?
  end

  def flow_recently_started?(conversation)
    flow = conversation.n8n_flow
    return false unless flow

    flow.last_triggered_at.present? && flow.last_triggered_at > 10.seconds.ago
  end

  def reload_conversation_state!(conversation)
    conversation.reload
    conversation.n8n_flow&.reload if conversation.n8n_flow&.persisted?
  end

  def ensure_pending_status!(conversation)
    return if conversation.pending?

    with_executor(agent_bot) { conversation.pending! }
  rescue StandardError => e
    Rails.logger.warn("[N8n] Failed to set pending: #{e.message}")
  end

  def ensure_open_status!(conversation)
    return unless conversation.pending?

    with_executor(agent_bot) { conversation.open! }
  rescue StandardError => e
    Rails.logger.warn("[N8n] Failed to set open: #{e.message}")
  end

  def with_executor(executor)
    previous = Current.executed_by
    Current.executed_by = executor
    yield
  ensure
    Current.executed_by = previous
  end

  # ===========================================
  # Payload Builders
  # ===========================================

  def conversation_payload(conversation, event)
    last_message = conversation.messages.incoming.last ||
                   conversation.messages.where.not(message_type: :activity).last
    build_payload(conversation, last_message, event)
  end

  def message_payload(message, event)
    build_payload(message.conversation, message, event)
  end

  def webwidget_payload(contact_inbox, event)
    {
      event: event_name(event),
      event_info: event.data[:event_info],
      contact: contact_data(contact_inbox.contact),
      inbox_id: contact_inbox.inbox_id
    }
  end

  def build_payload(conversation, message, event)
    payload = {
      event: event_name(event),
      conversation: conversation_data(conversation),
      contact: contact_data(conversation.contact)
    }
    payload[:message] = message_data(message) if message.present?
    payload
  end

  def conversation_data(conversation)
    {
      id: conversation.display_id,
      conversation_id: conversation.id,
      display_id: conversation.display_id,
      account_id: conversation.account_id,
      status: conversation.status,
      channel: conversation.inbox.channel_type,
      inbox_id: conversation.inbox_id,
      inbox_name: conversation.inbox.name,
      created_at: conversation.created_at.iso8601,
      updated_at: conversation.updated_at.iso8601
    }
  end

  def contact_data(contact)
    {
      id: contact.id,
      name: contact.name,
      email: contact.email,
      phone_number: contact.phone_number,
      identifier: contact.identifier,
      custom_attributes: contact.custom_attributes,
      additional_attributes: contact.additional_attributes
    }
  end

  def message_data(message)
    data = {
      id: message.id,
      content: message.content,
      content_type: message.content_type,
      message_type: message.message_type,
      created_at: message.created_at.iso8601,
      private: message.private
    }
    data[:attachments] = attachment_data(message) if message.attachments.present?
    data
  end

  def attachment_data(message)
    message.attachments.map do |attachment|
      {
        id: attachment.id,
        file_type: attachment.file_type,
        data_url: attachment.download_url
      }
    end
  end

  # ===========================================
  # Configuration Helpers
  # ===========================================

  # Start flow on first incoming message (NEW conversation)
  def start_on_message?
    flag = bot_config_value('n8n_start_on_message')
    return true if triggers_version == 1 && flag == false

    bot_config_flag('n8n_start_on_message', default: true)
  end

  # Start flow when agent manually sets conversation to pending (from ANY status)
  def start_on_manual_pending?
    bot_config_flag('n8n_start_on_manual_pending', default: true)
  end

  # Start flow when contact-triggered pending happens (status change events)
  def start_on_contact_pending?
    bot_config_flag('n8n_start_on_contact_pending', default: true)
  end

  def triggers_version
    (bot_config_value('n8n_triggers_version') || 1).to_i
  end

  # Start flow when customer message reopens a resolved conversation
  # If disabled, conversation goes to 'open' instead of 'pending'
  def start_on_reopen?
    # Support both old and new config key names for backward compatibility
    flag = bot_config_value('n8n_start_on_reopen')
    flag = bot_config_value('n8n_restart_on_reopen') if flag.nil?
    return true if flag.nil?

    to_boolean(flag)
  end

  def bot_config_flag(key, default: false)
    flag = bot_config_value(key)
    return default if flag.nil?

    to_boolean(flag)
  end

  def bot_config_value(key)
    agent_bot&.bot_config&.dig(key)
  end

  def to_boolean(value)
    ActiveRecord::Type::Boolean.new.cast(value) == true
  end

  # ===========================================
  # Infrastructure
  # ===========================================

  def orchestrator_for(conversation)
    ::Integrations::N8nFlowOrchestrator.new(conversation, agent_bot: agent_bot)
  end

  def clear_bot_assignment(conversation)
    return if agent_bot.blank?

    AgentBots::ClearAssignmentJob.perform_later(conversation.id, agent_bot.id)
    conversation.association(:assignee_agent_bot).reset if conversation.association(:assignee_agent_bot).loaded?
  end

  def touch_last_triggered(contact_inbox)
    conv = contact_inbox.conversations.order(:id).last
    return unless conv

    flow = conv.n8n_flow || conv.build_n8n_flow
    flow.update!(last_triggered_at: Time.current)
  end

  def event_name(event)
    event.try(:name) || event.try(:event) || event.try(:type) || 'unknown'
  end

  def log_error(action, error, context = {})
    context_str = context.map { |k, v| "#{k}=#{v}" }.join(' ')
    Rails.logger.error("[N8n] #{action} failed #{context_str} error=#{error.class} #{error.message}")
  end

  def log_debug(action, context = {})
    context_str = context.map { |k, v| "#{k}=#{v.inspect}" }.join(' ')
    Rails.logger.info("[N8n] #{action} #{context_str}")
  end
end
