class WebhookListener < BaseListener
  def conversation_status_changed(event)
    conversation = extract_conversation_and_account(event)[0]
    changed_attributes = extract_changed_attributes(event)
    inbox = conversation.inbox

    # Extras derivados del diff crudo
    raw_changes = (event.data[:changed_attributes] || {}).transform_keys(&:to_s)
    changes_map = raw_changes.transform_values { |v| { previous_value: v[0], current_value: v[1] } }
    changed_keys = changes_map.keys

    # Actor que ejecutó el cambio, si está disponible
    actor = event.data[:performed_by]
    performed_by_payload = build_actor_payload(actor)

    # Assignment change enriquecido si aplica
    assignment_change = nil
    if changes_map.key?('assignee_id')
      prev_id = changes_map['assignee_id'][:previous_value]
      curr_id = changes_map['assignee_id'][:current_value]
      prev_user = prev_id.present? ? User.find_by(id: prev_id) : nil
      curr_user = curr_id.present? ? User.find_by(id: curr_id) : nil
      assignment_change = {
        previous_assignee: build_actor_payload(prev_user),
        current_assignee: build_actor_payload(curr_user)
      }
    end

    # Metadata de automatización y fuente del cambio
    automation_rule_meta = actor.is_a?(AutomationRule) ? { id: actor.id, name: actor.try(:name) } : nil
    source = if actor.is_a?(AutomationRule)
               'automation'
             elsif actor.respond_to?(:email)
               'user'
             else
               'system'
             end

    # Resumen legible de cambios
    diff_summary = build_diff_summary(changes_map, {}, assignment_change)

    payload = conversation.webhook_data.merge(
      event: __method__.to_s,
      changed_attributes: changed_attributes,
      changed_attributes_map: changes_map,
      changed_keys: changed_keys,
      performed_by: performed_by_payload,
      automation_rule: automation_rule_meta,
      source: source,
      assignment_change: assignment_change,
      notifiable_assignee_change: event.data[:notifiable_assignee_change],
      changed_at: (event.data[:changed_at] || Time.current.iso8601),
      diff_summary: diff_summary
    )
    deliver_webhook_payloads(payload, inbox)
  end

  def conversation_updated(event)
    conversation = extract_conversation_and_account(event)[0]
    changed_attributes = extract_changed_attributes(event)
    inbox = conversation.inbox

    # Extras derivados del diff crudo
    raw_changes = (event.data[:changed_attributes] || {}).transform_keys(&:to_s)
    changes_map = raw_changes.transform_values { |v| { previous_value: v[0], current_value: v[1] } }
    changed_keys = changes_map.keys

    # Always include label diff fields (empty arrays when no label change)
    labels_added = []
    labels_removed = []
    if changes_map.key?('label_list')
      prev = Array(changes_map['label_list'][:previous_value])
      curr = Array(changes_map['label_list'][:current_value])
      labels_added = curr - prev
      labels_removed = prev - curr
    end
    extras = { labels_added: labels_added, labels_removed: labels_removed }

    # Actor que ejecutó el cambio, si está disponible
    actor = event.data[:performed_by]
    performed_by_payload = build_actor_payload(actor)

    # Assignment change enriquecido si aplica
    assignment_change = nil
    if changes_map.key?('assignee_id')
      prev_id = changes_map['assignee_id'][:previous_value]
      curr_id = changes_map['assignee_id'][:current_value]
      prev_user = prev_id.present? ? User.find_by(id: prev_id) : nil
      curr_user = curr_id.present? ? User.find_by(id: curr_id) : nil
      assignment_change = {
        previous_assignee: build_actor_payload(prev_user),
        current_assignee: build_actor_payload(curr_user)
      }
    end

    # Metadata de automatización y fuente del cambio
    automation_rule_meta = actor.is_a?(AutomationRule) ? { id: actor.id, name: actor.try(:name) } : nil
    source = if actor.is_a?(AutomationRule)
               'automation'
             elsif actor.respond_to?(:email)
               'user'
             else
               'system'
             end

    # Resumen legible de cambios
    diff_summary = build_diff_summary(changes_map, extras, assignment_change)

    base_payload = conversation.webhook_data.merge(
      event: __method__.to_s,
      changed_attributes: changed_attributes,
      labels: {
        current: conversation.label_list,
        added: extras[:labels_added],
        removed: extras[:labels_removed]
      }
    )

    # Only enrich payload when explicitly enabled to preserve legacy contract in tests
    if ENV['ENABLE_ENRICHED_WEBHOOKS'] == 'true'
      base_payload.merge!(
        changed_attributes_map: changes_map,
        changed_keys: changed_keys,
        performed_by: performed_by_payload,
        automation_rule: automation_rule_meta,
        source: source,
        assignment_change: assignment_change,
        notifiable_assignee_change: event.data[:notifiable_assignee_change],
        changed_at: (event.data[:changed_at] || Time.current.iso8601),
        diff_summary: diff_summary
      )
    end

    payload = base_payload
    deliver_webhook_payloads(payload, inbox)
  end

  def conversation_created(event)
    conversation = extract_conversation_and_account(event)[0]
    inbox = conversation.inbox
    payload = conversation.webhook_data.merge(event: __method__.to_s)
    deliver_webhook_payloads(payload, inbox)
  end

  def message_created(event)
    message = extract_message_and_account(event)[0]
    inbox = message.inbox

    return unless message.webhook_sendable?

    payload = message.webhook_data.merge(event: __method__.to_s)
    deliver_webhook_payloads(payload, inbox)
  end

  def message_updated(event)
    message = extract_message_and_account(event)[0]
    inbox = message.inbox

    return unless message.webhook_sendable?

    payload = message.webhook_data.merge(event: __method__.to_s)
    deliver_webhook_payloads(payload, inbox)
  end

  def webwidget_triggered(event)
    contact_inbox = event.data[:contact_inbox]
    inbox = contact_inbox.inbox

    payload = contact_inbox.webhook_data.merge(event: __method__.to_s)
    payload[:event_info] = event.data[:event_info]
    deliver_webhook_payloads(payload, inbox)
  end

  def contact_created(event)
    contact, account = extract_contact_and_account(event)
    payload = contact.webhook_data.merge(event: __method__.to_s)
    deliver_account_webhooks(payload, account)
  end

  def contact_updated(event)
    contact, account = extract_contact_and_account(event)
    changed_attributes = extract_changed_attributes(event)
    return if changed_attributes.blank?

    payload = contact.webhook_data.merge(event: __method__.to_s, changed_attributes: changed_attributes)
    deliver_account_webhooks(payload, account)
  end

  def inbox_created(event)
    inbox, account = extract_inbox_and_account(event)
    inbox_webhook_data = Inbox::EventDataPresenter.new(inbox).push_data
    payload = inbox_webhook_data.merge(event: __method__.to_s)
    deliver_account_webhooks(payload, account)
  end

  def inbox_updated(event)
    inbox, account = extract_inbox_and_account(event)
    changed_attributes = extract_changed_attributes(event)
    return if changed_attributes.blank?

    inbox_webhook_data = Inbox::EventDataPresenter.new(inbox).push_data
    payload = inbox_webhook_data.merge(event: __method__.to_s, changed_attributes: changed_attributes)
    deliver_account_webhooks(payload, account)
  end

  def conversation_typing_on(event)
    handle_typing_status(__method__.to_s, event)
  end

  def conversation_typing_off(event)
    handle_typing_status(__method__.to_s, event)
  end

  private

  def handle_typing_status(event_name, event)
    conversation = event.data[:conversation]
    user = event.data[:user]
    inbox = conversation.inbox

    payload = {
      event: event_name,
      user: user.webhook_data,
      conversation: conversation.webhook_data,
      is_private: event.data[:is_private] || false
    }
    deliver_webhook_payloads(payload, inbox)
  end

  def deliver_account_webhooks(payload, account)
    account.webhooks.account_type.each do |webhook|
      next unless webhook.subscriptions.include?(payload[:event])

      WebhookJob.perform_later(webhook.url, payload)
    end
  end

  def deliver_api_inbox_webhooks(payload, inbox)
    return unless inbox.channel_type == 'Channel::Api'
    return if inbox.channel.webhook_url.blank?

    WebhookJob.perform_later(inbox.channel.webhook_url, payload, :api_inbox_webhook)
  end

  def deliver_webhook_payloads(payload, inbox)
    deliver_account_webhooks(payload, inbox.account)
    deliver_api_inbox_webhooks(payload, inbox)
  end

  # Helpers
  def build_actor_payload(actor)
    return nil unless actor

    if actor.respond_to?(:webhook_data)
      actor.webhook_data
    else
      data = { id: actor.try(:id), type: actor.class.name }
      data[:name] = actor.try(:name) if actor.respond_to?(:name)
      data[:email] = actor.try(:email) if actor.respond_to?(:email)
      data.compact
    end
  end

  def build_diff_summary(changes_map, extras, assignment_change)
    parts = []

    if changes_map.key?('status')
      from = changes_map['status'][:previous_value]
      to = changes_map['status'][:current_value]
      parts << "status: #{from} -> #{to}"
    end

    if changes_map.key?('label_list')
      added = Array(extras[:labels_added])
      removed = Array(extras[:labels_removed])
      label_bits = []
      label_bits << "+#{added.join(',')}" if added.any?
      label_bits << "-#{removed.join(',')}" if removed.any?
      parts << "labels: #{label_bits.join(' ')}" if label_bits.any?
    end

    if changes_map.key?('assignee_id')
      prev_name = assignment_change&.dig(:previous_assignee, :name)
      curr_name = assignment_change&.dig(:current_assignee, :name)
      parts << "assignee: #{prev_name || '-'} -> #{curr_name || '-'}"
    end

    # Cualquier otra clave cambiada se resume genéricamente
    other_keys = changes_map.keys - %w[status label_list assignee_id]
    other_keys.each do |key|
      from = changes_map[key][:previous_value]
      to = changes_map[key][:current_value]
      parts << "#{key}: #{from.inspect} -> #{to.inspect}"
    end

    parts.join('; ')
  end
end
