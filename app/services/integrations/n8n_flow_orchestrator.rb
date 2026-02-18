class Integrations::N8nFlowOrchestrator
  attr_reader :conversation, :agent_bot

  def initialize(conversation, agent_bot: nil)
    @conversation = conversation
    @agent_bot = agent_bot
  end

  def start_or_update_with_full_url(payload:, start_url:)
    with_session do |flow|
      trigger_flow(flow: flow, payload: payload, start_url: start_url)
    end
  end

  def forward_with_stored_url(payload:)
    with_session do |flow|
      forward_payload(flow: flow, payload: payload)
    end
  end

  def forward_message(payload:)
    forward_with_stored_url(payload: payload)
  end

  def reset_flow
    with_session do |flow|
      flow.update!(flow_id: nil, flow_webhook_url: nil, last_message_id: nil, last_triggered_at: nil)
    end
  end

  private

  def with_session
    conversation.with_lock do
      flow = conversation.n8n_flow || conversation.build_n8n_flow
      flow.save! if flow.new_record?
      yield flow
    end
  end

  def trigger_flow(flow:, payload:, start_url:)
    # Mark as starting BEFORE HTTP call to prevent race conditions with message_created
    flow.update!(last_triggered_at: Time.current, flow_webhook_url: start_url)

    response = post_with_retries(start_url, payload)
    new_flow_id = extract_flow_id(response)
    last_message_id = extract_message_id(payload)

    flow.update!(
      flow_id: new_flow_id,
      last_message_id: last_message_id
    )

    assign_conversation_to_bot!
    new_flow_id
  rescue StandardError => e
    Rails.logger.error("[N8n] Error starting flow conversation_id=#{conversation.id} error=#{e.class} #{e.message}")
    # Clear the starting marker on failure
    flow.update_columns(last_triggered_at: nil, flow_webhook_url: nil) if flow.persisted? && flow.flow_id.blank?
    raise
  end

  def forward_payload(flow:, payload:)
    return if flow.flow_id.blank?

    ensure_bot_assignment(flow)

    url = waiting_url_for(flow)
    if url.blank?
      Rails.logger.error("[N8n] forward skipped due to invalid waiting URL conversation_id=#{conversation.id}")
      return
    end

    post_with_retries(url, payload)
    flow.update!(last_message_id: extract_message_id(payload), last_triggered_at: Time.current)
  rescue StandardError => e
    # Don't restart flow automatically - the flow might not be waiting for input
    # Log the error but keep the flow_id to prevent creating duplicate flows
    Rails.logger.warn("[N8n] forward failed conversation_id=#{conversation.id} flow_id=#{flow.flow_id} error=#{e.class} #{e.message}")
    Rails.logger.warn('[N8n] Flow continues running - not restarting. If flow should restart, use switch_flow API or change conversation status.')
  end

  def ensure_bot_assignment(flow)
    return if agent_bot.blank?
    return if flow.flow_id.blank?
    return if conversation.assignee_agent_bot_id == agent_bot.id
    return if conversation.assignee_id.present?

    conversation.update!(assignee_agent_bot: agent_bot, assignee: nil)
  end

  def assign_conversation_to_bot!
    return if agent_bot.blank?
    return if conversation.assignee_agent_bot_id == agent_bot.id
    return if conversation.assignee_id.present?

    conversation.update!(assignee_agent_bot: agent_bot, assignee: nil)
  end

  def restart_flow(flow:, payload:)
    start_url = flow.flow_webhook_url.presence || agent_bot&.outgoing_url
    if start_url.blank?
      Rails.logger.error("[N8n] restart skipped due to missing start_url conversation_id=#{conversation.id}")
      return
    end

    flow.update!(flow_id: nil)
    trigger_flow(flow: flow, payload: payload, start_url: start_url)
  end

  def post_with_retries(url, body, attempts: 3)
    tries = 0
    begin
      started_at = Time.zone.now
      response = http_post(url, body)
      duration_ms = ((Time.zone.now - started_at) * 1000).round
      code = response&.code.to_i
      if code.between?(200, 299)
        Rails.logger.info("[N8n] HTTP POST success url=#{safe_url(url)} code=#{code} dur_ms=#{duration_ms}")
        return response
      end

      retryable = retryable_status?(code)
      Rails.logger.warn("[N8n] HTTP POST non-2xx url=#{safe_url(url)} code=#{code} dur_ms=#{duration_ms} retryable=#{retryable}")

      raise "HTTP #{code}" unless retryable

      raise "HTTP #{code} (retryable)"
    rescue StandardError => e
      tries += 1
      if tries < attempts
        sleep_seconds = backoff_with_jitter(tries)
        Rails.logger.info("[N8n] retrying attempt=#{tries} sleep=#{sleep_seconds}s url=#{safe_url(url)} error=#{e.message}")
        sleep(sleep_seconds)
        retry
      end
      Rails.logger.error("[N8n] HTTP POST failed attempts=#{tries} url=#{safe_url(url)} error=#{e.class} #{e.message}")
      raise e
    end
  end

  def http_post(url, body)
    HTTParty.post(url, headers: { 'Content-Type' => 'application/json' }, body: body.to_json, timeout: 8)
  end

  def retryable_status?(code)
    return true if code.zero?
    return true if code == 408 || code == 429
    return true if code.between?(500, 599)

    false
  end

  def backoff_with_jitter(tries)
    base = 0.25 * (2 ** (tries - 1))
    jitter = rand(0.0..(base / 2.0))
    (base + jitter).round(3)
  end

  def safe_url(url)
    URI.parse(url).then do |uri|
      port_part = if (uri.scheme == 'https' && uri.port == 443) || (uri.scheme == 'http' && uri.port == 80)
                    ''
                  else
                    ":#{uri.port}"
                  end
      "#{uri.scheme}://#{uri.host}#{port_part}#{uri.path}"
    end
  rescue URI::InvalidURIError
    '<invalid-url>'
  end

  def waiting_url_for(flow)
    return if flow.flow_webhook_url.blank? || flow.flow_id.blank?

    URI.parse(flow.flow_webhook_url).then do |uri|
      path = uri.path || ''
      prefix = if path.include?('/webhook/')
                 path.split('/webhook/').first
               else
                 path.gsub(%r{/+$}, '')
               end

      port_part = if (uri.scheme == 'https' && uri.port == 443) || (uri.scheme == 'http' && uri.port == 80)
                    ''
                  else
                    ":#{uri.port}"
                  end

      base = "#{uri.scheme}://#{uri.host}#{port_part}#{prefix}".gsub(%r{/+$}, '')
      "#{base}/webhook-waiting/#{flow.flow_id}"
    end
  rescue URI::InvalidURIError => e
    Rails.logger.error("[N8n] Invalid webhook URL conversation_id=#{conversation.id} error=#{e.class} #{e.message}")
    nil
  end

  def extract_flow_id(response)
    body = response.respond_to?(:parsed_response) ? response.parsed_response : nil
    flow_id = body.is_a?(Hash) ? body['id'] : nil
    flow_id.presence || "execution-#{Time.now.to_i}"
  end

  def extract_message_id(payload)
    return unless payload.is_a?(Hash)

    payload['id'] || payload.dig('messages', 0, 'id')
  end
end
