class Webhooks::WhatsappCallsController < ActionController::API
  before_action :set_channel
  before_action :verify_webhook_signature, only: [:create]

  def create
    Rails.logger.info '[WHATSAPP_CALLS] ========== WEBHOOK RECEIVED =========='
    Rails.logger.info "[WHATSAPP_CALLS] Request body: #{request.body.read}"
    request.body.rewind
    Rails.logger.info "[WHATSAPP_CALLS] Headers: #{request.headers.env.select { |k, _v| k.start_with?('HTTP_') }.inspect}"

    process_webhook_payload
    head :ok
  rescue StandardError => e
    Rails.logger.error "[WHATSAPP_CALLS] Webhook processing failed: #{e.message}"
    Rails.logger.error e.backtrace.join("\n")
    head :unprocessable_entity
  end

  def verify
    if valid_verification_request?
      render plain: params['hub.challenge']
    else
      head :forbidden
    end
  end

  private

  def set_channel
    phone_number = params[:phone_number_id] || extract_phone_number_from_webhook
    @channel = ::Channel::Whatsapp.find_by!(
      provider_config: { phone_number_id: phone_number }
    )
    @inbox = @channel.inbox
  rescue ActiveRecord::RecordNotFound
    Rails.logger.error "[WHATSAPP_CALLS] Channel not found for phone_number_id: #{phone_number}"
    head :not_found
  end

  def extract_phone_number_from_webhook
    webhook_data = JSON.parse(request.body.read)
    request.body.rewind
    webhook_data.dig('entry', 0, 'changes', 0, 'value', 'metadata', 'phone_number_id')
  end

  def process_webhook_payload
    webhook_data = JSON.parse(request.body.read)
    entry = webhook_data['entry']&.first
    return unless entry

    changes = entry['changes']&.first
    return unless changes

    field = changes['field']
    return unless field == 'calls'

    value = changes['value']
    process_call_event(value)
  end

  def process_call_event(value)
    if value['calls']
      handle_call_webhook(value)
    elsif value['statuses']
      handle_status_webhook(value)
    end
  end

  def handle_call_webhook(value)
    call_data = value['calls'].first
    event = call_data['event']

    case event
    when 'connect'
      handle_call_connect(call_data, value['metadata'])
    when 'terminate'
      handle_call_terminate(call_data, value['metadata'])
    else
      Rails.logger.info "[WHATSAPP_CALLS] Unknown call event: #{event}"
    end
  end

  def handle_call_connect(call_data, metadata)
    call_id = call_data['id']

    if call_id.blank?
      Rails.logger.error '[WHATSAPP_CALLS] Missing call_id in connect event'
      return
    end

    direction = call_data['direction']

    unless %w[USER_INITIATED BUSINESS_INITIATED].include?(direction)
      Rails.logger.error "[WHATSAPP_CALLS] Invalid call direction: #{direction}"
      return
    end

    if direction == 'USER_INITIATED'
      Whatsapp::Calling::InboundCallJob.perform_later(
        account_id: @channel.account_id,
        inbox_id: @inbox.id,
        call_data: call_data,
        metadata: metadata
      )
    elsif direction == 'BUSINESS_INITIATED'
      Whatsapp::Calling::BusinessCallConnectJob.perform_later(
        account_id: @channel.account_id,
        inbox_id: @inbox.id,
        call_data: call_data,
        metadata: metadata
      )
    end
  end

  def handle_call_terminate(call_data, metadata)
    call_id = call_data['id']

    if call_id.blank?
      Rails.logger.error '[WHATSAPP_CALLS] Missing call_id in terminate event'
      return
    end

    Whatsapp::Calling::CallTerminateJob.perform_later(
      account_id: @channel.account_id,
      inbox_id: @inbox.id,
      call_data: call_data,
      metadata: metadata
    )
  end

  def handle_status_webhook(value)
    status_data = value['statuses'].first

    unless status_data && status_data['id'].present?
      Rails.logger.error '[WHATSAPP_CALLS] Invalid status data in webhook'
      return
    end

    Whatsapp::Calling::CallStatusJob.perform_later(
      account_id: @channel.account_id,
      inbox_id: @inbox.id,
      status_data: status_data,
      metadata: value['metadata']
    )
  end

  def verify_webhook_signature
    signature = request.headers['X-Hub-Signature-256']

    if signature.blank?
      Rails.logger.warn "[SECURITY][#{request.remote_ip}] Missing webhook signature"
      return head :unauthorized
    end

    # Simple in-memory rate limiting (consider using Redis for production)
    rate_limit_key = "webhook_rate_limit:#{request.remote_ip}"
    current_count = Rails.cache.read(rate_limit_key) || 0

    if current_count >= 100
      Rails.logger.warn "[SECURITY][#{request.remote_ip}] Rate limit exceeded"
      return head :too_many_requests
    end

    Rails.cache.write(rate_limit_key, current_count + 1, expires_in: 1.minute)

    app_secret = @channel.provider_config['app_secret'] || ENV.fetch('WHATSAPP_APP_SECRET', nil)
    return unless app_secret

    payload = request.raw_post
    expected_signature = OpenSSL::HMAC.hexdigest('SHA256', app_secret, payload)
    expected = "sha256=#{expected_signature}"

    return if Rack::Utils.secure_compare(signature, expected)

    Rails.logger.error "[SECURITY][#{request.remote_ip}] Invalid webhook signature"
    head :unauthorized
  end

  def valid_verification_request?
    verify_token = @channel.provider_config['webhook_verify_token']
    params['hub.mode'] == 'subscribe' &&
      params['hub.verify_token'] == verify_token &&
      params['hub.challenge'].present?
  end
end
