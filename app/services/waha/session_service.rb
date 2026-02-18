# frozen_string_literal: true

# Service to interact with WAHA API for session management.
# This service only handles session orchestration - messaging is handled
# by Channel::Api through WAHA's native Chatwoot App integration.
#
class Waha::SessionService
  class ApiError < StandardError; end

  BASE_PATH = '/api'

  def initialize(waha_session:)
    @session = waha_session
    @config = @session.waha_config
    validate_config!
  end

  def validate_config!
    if @config['api_key'].blank?
      Rails.logger.error("[WAHA] API key is missing for account #{@session.account_id}")
      raise ApiError, 'WAHA API key is not configured. Please configure it in Account Settings.'
    end

    return if @config['base_url'].present?

    Rails.logger.error("[WAHA] Base URL is missing for account #{@session.account_id}")
    raise ApiError, 'WAHA base URL is not configured. Please configure it in Account Settings.'
  end

  # Main setup: create session in WAHA and configure Chatwoot App
  def setup_session
    Rails.logger.info("[WAHA] Setting up session: #{@session.session_name}")

    create_or_update_waha_session
    configure_chatwoot_app
    fetch_qr_code

    Rails.logger.info("[WAHA] Session setup complete: #{@session.session_name}")
  rescue StandardError => e
    Rails.logger.error("[WAHA] Session setup failed: #{e.message}")
    @session.update!(status: 'failed', waha_data: (@session.waha_data || {}).merge('error' => e.message))
    raise
  end

  def create_or_update_waha_session
    config = {
      name: @session.session_name,
      start: true,
      config: build_session_config
    }

    begin
      Rails.logger.info("[WAHA] Creating session in WAHA name=#{@session.session_name}")
      response = post('/sessions', config)
      Rails.logger.info("[WAHA] Session create response: #{response}")
      @session.update!(status: 'starting', waha_data: response)
    rescue ApiError => e
      raise unless e.message.include?('422') || e.message.include?('already exists')

      Rails.logger.info('[WAHA] Session exists, fetching status...')
      get_status
    end
  end

  def configure_chatwoot_app
    webhook_url = @session.inbox_webhook_url
    raise ApiError, 'Inbox webhook URL not available' if webhook_url.blank?

    waha_webhook = @session.waha_webhook_url
    app_id = @session.waha_app_id
    api_token = admin_api_token

    Rails.logger.info(
      "[WAHA] Configuring Chatwoot App app_id=#{app_id} " \
      "session=#{@session.session_name} inbox_identifier=#{@session.inbox_identifier} " \
      "webhook_url_present=#{webhook_url.present?} waha_webhook_present=#{waha_webhook.present?}"
    )

    app_config = build_app_config(app_id: app_id, api_token: api_token, webhook_url: webhook_url, waha_webhook: waha_webhook)

    upsert_app(app_id, app_config)
    configure_channel_webhook(app_id)

    # Cache latest app details from WAHA
    app_details = fetch_app_details(app_id)
    @session.update!(waha_data: (@session.waha_data || {}).merge('app' => app_details)) if app_details.present?

    @session.update!(waha_data: (@session.waha_data || {}).merge('app_id' => app_id))
  end

  def fetch_qr_code
    url = "#{@config['base_url']}#{BASE_PATH}/#{@session.session_name}/auth/qr"

    response = HTTParty.get(url, {
                              headers: { 'X-Api-Key' => @config['api_key'], 'Accept' => 'image/png' },
                              timeout: 30
                            })

    return nil unless response.success?

    body = response.body.dup.force_encoding('BINARY')
    png_signature = "\x89PNG".dup.force_encoding('BINARY')

    if body.start_with?(png_signature)
      qr_data_url = "data:image/png;base64,#{Base64.strict_encode64(body)}"
      @session.update!(qr_code: qr_data_url, qr_code_generated_at: Time.current, status: 'scan_qr')
      qr_data_url
    else
      # Try JSON response
      begin
        json = JSON.parse(body)
        if json['data'].present?
          qr_data_url = "data:#{json['mimetype'] || 'image/png'};base64,#{json['data']}"
          @session.update!(qr_code: qr_data_url, qr_code_generated_at: Time.current, status: 'scan_qr')
          return qr_data_url
        end
      rescue JSON::ParserError
        # Not JSON
      end
      nil
    end
  end

  def refresh_qr_code
    fetch_qr_code
  end

  def get_status
    response = get("/sessions/#{@session.session_name}")
    waha_status = response['status']

    # Check if connected via me.id
    if response.dig('me', 'id').present?
      waha_status = 'CONNECTED'
      phone = response.dig('me', 'id')&.split('@')&.first
      @session.update!(phone_number: phone) if phone.present? && @session.phone_number != phone
    end

    @session.update_status_from_waha(waha_status)
    @session.update!(waha_data: (@session.waha_data || {}).merge('last_status' => response))

    response
  rescue ApiError => e
    if e.message.include?('404')
      Rails.logger.warn("[WAHA] Session not found remotely name=#{@session.session_name}: #{e.message}")
      @session.update!(status: 'failed', waha_data: (@session.waha_data || {}).merge('last_error' => e.message))
      return { 'status' => 'NOT_FOUND', 'error' => e.message }
    end

    raise
  end

  # Get session configuration from WAHA (source of truth)
  def get_session_config
    response = get("/sessions/#{@session.session_name}")

    # Extract config from WAHA response
    waha_config = response['config'] || {}

    # Sync to our DB as cache
    sync_config_to_db(waha_config)

    response
  end

  # Sync WAHA config to our database
  def sync_config_to_db(waha_config)
    updates = {}

    updates[:debug] = waha_config['debug'] if waha_config.key?('debug')
    updates[:metadata] = waha_config['metadata'] if waha_config.key?('metadata')

    if waha_config['noweb'].is_a?(Hash) && waha_config['noweb']['store'].is_a?(Hash)
      store = waha_config['noweb']['store']
      updates[:noweb_store_enabled] = store['enabled'] if store.key?('enabled')
      updates[:noweb_store_full_sync] = store['fullSync'] if store.key?('fullSync')
    end

    if waha_config['ignore'].is_a?(Hash)
      ignore = waha_config['ignore']
      updates[:ignore_groups] = ignore['groups'] if ignore.key?('groups')
      updates[:ignore_channels] = ignore['channels'] if ignore.key?('channels')
      updates[:ignore_status] = ignore['status'] if ignore.key?('status')
      updates[:ignore_broadcast] = ignore['broadcast'] if ignore.key?('broadcast')
    end

    if waha_config['proxy'].is_a?(Hash)
      proxy = waha_config['proxy']
      updates[:proxy_server] = proxy['server'] if proxy.key?('server')
      updates[:proxy_username] = proxy['username'] if proxy.key?('username')
      # Don't sync password back for security
    end

    @session.update!(updates) if updates.any?

    Rails.logger.info("[WAHA] Synced config from WAHA to DB: #{updates.keys.join(', ')}")
  end

  def restart_session
    post("/sessions/#{@session.session_name}/restart")
    @session.update!(status: 'starting')
  end

  # Reconfigure Chatwoot App in WAHA without recreating the session.
  def recreate_chatwoot_app
    configure_chatwoot_app
  end

  # Update session configuration in WAHA
  def update_session_config
    config = {
      name: @session.session_name,
      config: build_session_config
    }

    Rails.logger.info("[WAHA] Updating session config: #{config.inspect}")
    response = put("/sessions/#{@session.session_name}", config)
    Rails.logger.info("[WAHA] Session updated: #{response.inspect}")

    # Update local status from response
    @session.update_status_from_waha(response['status']) if response['status']

    response
  end

  def logout_session
    post("/sessions/#{@session.session_name}/logout")
    @session.update!(status: 'stopped', phone_number: nil, qr_code: nil)
  end

  def delete_session
    delete("/sessions/#{@session.session_name}")
  rescue ApiError => e
    Rails.logger.warn("[WAHA] Failed to delete session: #{e.message}")
  end

  private

  def get(path)
    request(:get, path)
  end

  def post(path, body = nil)
    request(:post, path, body)
  end

  def put(path, body = nil)
    request(:put, path, body)
  end

  def delete(path)
    request(:delete, path)
  end

  def request(method, path, body = nil)
    url = "#{@config['base_url']}#{BASE_PATH}#{path}"
    api_key = @config['api_key']
    api_key_masked = api_key.present? ? "#{api_key[0..3]}...#{api_key[-4..]}" : 'MISSING'

    options = {
      headers: {
        'X-Api-Key' => api_key,
        'Content-Type' => 'application/json',
        'Accept' => 'application/json'
      },
      timeout: 30
    }
    options[:body] = body.to_json if body.present?

    Rails.logger.info("[WAHA] request method=#{method} url=#{url} body_present=#{body.present?} api_key=#{api_key_masked}")

    response = HTTParty.send(method, url, options)

    unless response.success?
      Rails.logger.error("[WAHA] API error code=#{response.code} body=#{response.body} api_key=#{api_key_masked}")

      raise ApiError, "WAHA API authentication failed (403). Check if API key is correct: #{api_key_masked}" if response.code == 403

      raise ApiError, "WAHA API error: #{response.code} - #{response.body}"
    end

    parsed = response.parsed_response
    Rails.logger.info("[WAHA] response code=#{response.code} parsed=#{parsed}")
    parsed
  end

  def build_session_config
    config = {
      debug: @session.debug || false,
      noweb: {
        store: {
          enabled: @session.noweb_store_enabled.nil? || @session.noweb_store_enabled,
          fullSync: @session.noweb_store_full_sync || false
        }
      }
    }

    # Add metadata (always include, even if empty)
    config[:metadata] = (@session.metadata.presence || {})

    # Add ignore config (build it with all fields)
    ignore = {
      groups: @session.ignore_groups || false,
      channels: @session.ignore_channels.nil? || @session.ignore_channels,
      status: @session.ignore_status.nil? || @session.ignore_status,
      broadcast: @session.ignore_broadcast.nil? || @session.ignore_broadcast
    }
    config[:ignore] = ignore

    # Add proxy if configured
    if @session.proxy_server.present?
      proxy = { server: @session.proxy_server }
      proxy[:username] = @session.proxy_username if @session.proxy_username.present?
      proxy[:password] = @session.proxy_password if @session.proxy_password.present?
      config[:proxy] = proxy
    end

    # Always include empty webhooks array (WAHA expects it)
    config[:webhooks] = []

    config
  end

  def admin_api_token
    @admin_api_token ||= begin
      admin = @session.account.administrators.first
      raise ApiError, 'No admin user found for account' if admin.blank?

      admin.access_token&.token || admin.create_access_token!.token
    end
  end

  def build_app_config(app_id:, api_token:, webhook_url:, waha_webhook:)
    config = {
      id: app_id,
      app: 'chatwoot', # WAHA >= v2024.12 requires explicit app type
      session: @session.session_name,
      config: {
        url: ENV.fetch('FRONTEND_URL', 'http://localhost:3000'),
        token: api_token,
        inboxIdentifier: @session.inbox_identifier,
        accountId: @session.account_id,
        inboxId: @session.inbox_id,
        accountToken: api_token,
        sendFirstMessage: true,
        sendOpenConversation: true,
        sendCloseConversation: true,
        replyToQuotedMessage: true,
        webhookUrl: waha_webhook.presence
      }
    }

    # Do not send nil webhookUrl keys to WAHA
    config[:config].delete(:webhookUrl) if config[:config][:webhookUrl].nil?
    config
  end

  def upsert_app(app_id, app_config)
    existing = nil

    begin
      existing = get("/apps/#{app_id}")
      Rails.logger.info("[WAHA] Existing app response: #{existing}") if existing.present?
    rescue ApiError => e
      raise unless e.message.include?('404')
    end

    if existing.present?
      put("/apps/#{app_id}", app_config)
    else
      Rails.logger.info("[WAHA] App not found, creating app_id=#{app_id}")
      post('/apps', app_config)
    end
  end

  def fetch_app_details(app_id)
    get("/apps/#{app_id}")
  rescue ApiError => e
    Rails.logger.warn("[WAHA] Failed to fetch app details app_id=#{app_id}: #{e.message}")
    nil
  end

  def configure_channel_webhook(app_id)
    channel = @session.api_channel
    webhook = @session.waha_webhook_url
    return if channel.blank? || webhook.blank?

    if channel.webhook_url != webhook
      Rails.logger.info("[WAHA] Updating channel webhook to #{webhook}")
      channel.update!(webhook_url: webhook)
    end

    @session.update!(waha_data: (@session.waha_data || {}).merge('webhook_url' => webhook, 'app_id' => app_id))
  end
end
