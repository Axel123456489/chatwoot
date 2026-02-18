# frozen_string_literal: true

class Api::V1::Accounts::WahaSessionsController < Api::V1::Accounts::BaseController
  before_action :check_waha_enabled
  before_action :set_waha_session, only: %i[show update destroy status qr_code restart logout recreate_app update_config sync_config]

  def index
    @waha_sessions = Current.account.waha_sessions.includes(:inbox)
    render json: @waha_sessions.map { |s| session_json(s) }
  end

  def show
    render json: session_json(@waha_session)
  end

  # Create a new WAHA WhatsApp inbox with API channel
  def create
    ActiveRecord::Base.transaction do
      # 1. Create API channel (native Chatwoot)
      @channel = Channel::Api.create!(account: Current.account, hmac_mandatory: false)

      # 2. Create inbox
      @inbox = Current.account.inboxes.create!(
        name: params[:name] || 'WAHA WhatsApp',
        channel: @channel,
        greeting_enabled: false
      )

      # 3. Create WahaSession
      @waha_session = Current.account.waha_sessions.create!(inbox: @inbox)
    end

    # 4. Setup WAHA session asynchronously
    Waha::SetupSessionJob.perform_later(@waha_session.id)

    render json: session_json(@waha_session), status: :created
  rescue ActiveRecord::RecordInvalid => e
    render json: { error: e.message }, status: :unprocessable_entity
  end

  def update
    if @waha_session.update(waha_session_params)
      render json: session_json(@waha_session)
    else
      render json: { errors: @waha_session.errors }, status: :unprocessable_entity
    end
  end

  def destroy
    service = Waha::SessionService.new(waha_session: @waha_session)
    begin
      service.delete_session
    rescue StandardError
      nil
    end

    inbox = @waha_session.inbox
    @waha_session.destroy!
    inbox.destroy! if params[:delete_inbox] == 'true'

    head :no_content
  end

  def status
    service = Waha::SessionService.new(waha_session: @waha_session)
    waha_response = service.get_status

    render json: {
      status: @waha_session.status,
      phone_number: @waha_session.phone_number,
      connected: @waha_session.connected?,
      waha_status: waha_response['status'],
      waha_data: waha_response,
      app: @waha_session.waha_data&.dig('app')
    }
  rescue Waha::SessionService::ApiError => e
    status_code = e.message.include?('404') ? :not_found : :service_unavailable
    render json: { error: e.message, status: @waha_session.status }, status: status_code
  end

  def qr_code
    service = Waha::SessionService.new(waha_session: @waha_session)

    if @waha_session.qr_code_expired? || params[:refresh] == 'true'
      service.refresh_qr_code
      @waha_session.reload
    end

    render json: {
      qr_code: @waha_session.qr_code,
      generated_at: @waha_session.qr_code_generated_at,
      expired: @waha_session.qr_code_expired?,
      status: @waha_session.status
    }
  rescue Waha::SessionService::ApiError => e
    render json: { error: e.message }, status: :service_unavailable
  end

  def restart
    service = Waha::SessionService.new(waha_session: @waha_session)
    service.restart_session
    render json: { message: 'Session restarting', status: @waha_session.status }
  rescue Waha::SessionService::ApiError => e
    render json: { error: e.message }, status: :service_unavailable
  end

  def logout
    service = Waha::SessionService.new(waha_session: @waha_session)
    service.logout_session
    render json: { message: 'Logged out successfully', status: @waha_session.status }
  rescue Waha::SessionService::ApiError => e
    render json: { error: e.message }, status: :service_unavailable
  end

  def recreate_app
    service = Waha::SessionService.new(waha_session: @waha_session)
    service.recreate_chatwoot_app
    render json: { message: 'WAHA app recreated successfully', status: @waha_session.status }
  rescue Waha::SessionService::ApiError => e
    render json: { error: e.message }, status: :service_unavailable
  end

  def update_config
    if @waha_session.update(config_params)
      # Update session configuration in WAHA server
      service = Waha::SessionService.new(waha_session: @waha_session)
      begin
        service.update_session_config
      rescue Waha::SessionService::ApiError => e
        Rails.logger.error("[WAHA] Failed to update session config in WAHA: #{e.message}")
        # Continue even if WAHA update fails - config is saved in DB
      end

      @waha_session.reload
      render json: session_json(@waha_session)
    else
      render json: { errors: @waha_session.errors }, status: :unprocessable_entity
    end
  end

  def sync_config
    service = Waha::SessionService.new(waha_session: @waha_session)
    waha_session_data = service.get_session_config

    @waha_session.reload
    render json: {
      message: 'Configuration synced from WAHA',
      session: session_json(@waha_session),
      waha_config: waha_session_data['config']
    }
  rescue Waha::SessionService::ApiError => e
    render json: { error: e.message }, status: :service_unavailable
  end

  private

  def check_waha_enabled
    waha_config = Current.account.waha_integration
    return if waha_config&.dig('enabled') == true

    render json: { error: 'WAHA integration is not enabled' }, status: :forbidden
  end

  def set_waha_session
    @waha_session = Current.account.waha_sessions.find(params[:id])
  end

  def waha_session_params
    params.require(:waha_session).permit(:status)
  end

  def config_params
    params.permit(
      :debug,
      :ignore_groups,
      :ignore_channels,
      :ignore_status,
      :ignore_broadcast,
      :proxy_server,
      :proxy_username,
      :proxy_password,
      :noweb_store_enabled,
      :noweb_store_full_sync,
      metadata: {}
    )
  end

  def session_json(session)
    {
      id: session.id,
      session_name: session.session_name,
      status: session.status,
      phone_number: session.phone_number,
      connected: session.connected?,
      qr_code: session.qr_code,
      qr_code_expired: session.qr_code_expired?,
      debug: session.debug,
      metadata: session.metadata,
      ignore_groups: session.ignore_groups,
      ignore_channels: session.ignore_channels,
      ignore_status: session.ignore_status,
      ignore_broadcast: session.ignore_broadcast,
      proxy_server: session.proxy_server,
      proxy_username: session.proxy_username,
      noweb_store_enabled: session.noweb_store_enabled,
      noweb_store_full_sync: session.noweb_store_full_sync,
      inbox: {
        id: session.inbox.id,
        name: session.inbox.name,
        channel_type: session.inbox.channel_type,
        channel_id: session.channel&.id,
        identifier: session.inbox_identifier
      },
      created_at: session.created_at,
      updated_at: session.updated_at
    }
  end
end
