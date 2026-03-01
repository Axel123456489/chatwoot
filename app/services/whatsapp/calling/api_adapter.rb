class Whatsapp::Calling::ApiAdapter
  # Custom error classes for better error handling
  class NetworkError < StandardError; end

  class RateLimitError < StandardError
    attr_reader :retry_after

    def initialize(message, retry_after: 60)
      super(message)
      @retry_after = retry_after
    end
  end

  class ApiError < StandardError; end
  class TimeoutError < StandardError; end

  attr_reader :channel

  # Circuit breaker instance (class-level, shared across instances)
  @circuit_breaker = CircuitBreaker.new('whatsapp_api', failure_threshold: 5, timeout: 60)

  class << self
    attr_reader :circuit_breaker
  end

  def initialize(channel)
    @channel = channel
    @config = channel.provider_config
  end

  def initiate_call(to:, sdp_offer:, tracking_data: nil)
    phone_number_id = @config['phone_number_id']

    payload = {
      messaging_product: 'whatsapp',
      to: to,
      action: 'connect',
      session: {
        sdp_type: 'offer',
        sdp: sdp_offer
      }
    }

    payload[:biz_opaque_callback_data] = tracking_data if tracking_data

    make_api_call(
      endpoint: "#{phone_number_id}/calls",
      method: :post,
      payload: payload
    )
  end

  def pre_accept_call(call_id:, sdp_answer:)
    phone_number_id = @config['phone_number_id']

    payload = {
      messaging_product: 'whatsapp',
      call_id: call_id,
      action: 'pre_accept',
      session: {
        sdp_type: 'answer',
        sdp: sdp_answer
      }
    }

    make_api_call(
      endpoint: "#{phone_number_id}/calls",
      method: :post,
      payload: payload
    )
  end

  def accept_call(call_id:, sdp_answer:, tracking_data: nil)
    phone_number_id = @config['phone_number_id']

    payload = {
      messaging_product: 'whatsapp',
      call_id: call_id,
      action: 'accept',
      session: {
        sdp_type: 'answer',
        sdp: sdp_answer
      }
    }

    payload[:biz_opaque_callback_data] = tracking_data if tracking_data

    make_api_call(
      endpoint: "#{phone_number_id}/calls",
      method: :post,
      payload: payload
    )
  end

  def reject_call(call_id:)
    phone_number_id = @config['phone_number_id']

    payload = {
      messaging_product: 'whatsapp',
      call_id: call_id,
      action: 'reject'
    }

    make_api_call(
      endpoint: "#{phone_number_id}/calls",
      method: :post,
      payload: payload
    )
  end

  def terminate_call(call_id:)
    phone_number_id = @config['phone_number_id']

    payload = {
      messaging_product: 'whatsapp',
      call_id: call_id,
      action: 'terminate'
    }

    make_api_call(
      endpoint: "#{phone_number_id}/calls",
      method: :post,
      payload: payload
    )
  end

  # Fetches calling settings from Meta Graph API
  def fetch_calling_settings
    phone_number_id = @config['phone_number_id']
    make_api_call(endpoint: "#{phone_number_id}/settings?fields=calling", method: :get)
  end

  # Pushes calling settings to Meta Graph API (best-effort)
  def update_calling_settings(settings:)
    phone_number_id = @config['phone_number_id']

    calling_payload = {}
    calling_payload[:status] = settings[:status] if settings[:status]
    calling_payload[:call_icon_visibility] = settings[:call_icon_visibility] if settings[:call_icon_visibility]
    calling_payload[:callback_permission_status] = settings[:callback_permission_status] if settings[:callback_permission_status]

    if settings[:call_icons].present?
      calling_payload[:call_icons] = settings[:call_icons]
    end

    if settings[:call_hours]
      ch = settings[:call_hours]
      hours_payload = { status: ch[:status] }

      # Meta requires timezone_id and weekly_operating_hours even when status is DISABLED
      hours_payload[:timezone_id] = ch[:timezone_id].presence || 'UTC'

      if ch[:weekly_operating_hours].present?
        hours_payload[:weekly_operating_hours] = ch[:weekly_operating_hours].map do |h|
          {
            day_of_week: h[:day_of_week] || h['day_of_week'],
            open_time: (h[:open_time] || h['open_time']).to_s.delete(':'),
            close_time: (h[:close_time] || h['close_time']).to_s.delete(':')
          }
        end
      else
        # Provide a default schedule so Meta's required field constraint is satisfied
        hours_payload[:weekly_operating_hours] = [
          { day_of_week: 'MONDAY', open_time: '0900', close_time: '1700' },
          { day_of_week: 'TUESDAY', open_time: '0900', close_time: '1700' },
          { day_of_week: 'WEDNESDAY', open_time: '0900', close_time: '1700' },
          { day_of_week: 'THURSDAY', open_time: '0900', close_time: '1700' },
          { day_of_week: 'FRIDAY', open_time: '0900', close_time: '1700' }
        ]
      end

      if ch[:status] == 'ENABLED' && ch[:holiday_schedule].present?
        hours_payload[:holiday_schedule] = ch[:holiday_schedule].map do |h|
          {
            date: h[:date] || h['date'],
            start_time: (h[:start_time] || h['start_time']).to_s.delete(':'),
            end_time: (h[:end_time] || h['end_time']).to_s.delete(':')
          }
        end
      end

      calling_payload[:call_hours] = hours_payload
    end

    full_payload = { calling: calling_payload }
    make_api_call(endpoint: "#{phone_number_id}/settings", method: :post, payload: full_payload)
  end

  # Sends a standard WhatsApp message (used for permission requests)
  def send_message(message_params)
    phone_number_id = @config['phone_number_id']

    payload = {
      messaging_product: 'whatsapp',
      recipient_type: 'individual'
    }.merge(message_params)

    make_api_call(
      endpoint: "#{phone_number_id}/messages",
      method: :post,
      payload: payload
    )
  end

  private

  def make_api_call(endpoint:, method:, payload: nil, retries: 0)
    url = "#{api_base_url}/#{endpoint}"

    # Use circuit breaker to prevent cascading failures
    self.class.circuit_breaker.call do
      response = HTTParty.send(
        method,
        url,
        headers: {
          'Authorization' => "Bearer #{access_token}",
          'Content-Type' => 'application/json'
        },
        body: payload&.to_json,
        timeout: 10,      # 10 seconds read timeout
        open_timeout: 5   # 5 seconds connection timeout
      )

      handle_response(response)
    end
  rescue Net::OpenTimeout, Net::ReadTimeout => e
    if retries < 2
      sleep(2**retries) # Exponential backoff: 1s, 2s
      return make_api_call(endpoint: endpoint, method: method, payload: payload, retries: retries + 1)
    end
    Rails.logger.error "[WhatsApp API] Timeout error after #{retries + 1} attempts: #{e.message}"
    raise TimeoutError, 'WhatsApp API request timed out'
  rescue SocketError, Errno::ECONNREFUSED => e
    Rails.logger.error "[WhatsApp API] Network error: #{e.message}"
    raise NetworkError, 'Cannot connect to WhatsApp API'
  rescue CircuitBreaker::CircuitBreakerOpenError => e
    Rails.logger.warn "[WhatsApp API] #{e.message}"
    raise NetworkError, 'WhatsApp API temporarily unavailable'
  end

  def handle_response(response)
    case response.code
    when 200..299
      response.parsed_response
    when 429
      retry_after = response.headers['retry-after']&.to_i || 60
      error_message = response.parsed_response.dig('error', 'message') || 'Rate limit exceeded'
      Rails.logger.warn "[WhatsApp API] Rate limit hit, retry after #{retry_after}s"
      raise RateLimitError.new(error_message, retry_after: retry_after)
    when 400..499
      error_message = response.parsed_response.dig('error', 'message') || response.body
      Rails.logger.error "[WhatsApp API] Client error (#{response.code}): #{error_message}"
      raise ApiError, "WhatsApp API Error: #{error_message}"
    when 500..599
      error_message = response.parsed_response.dig('error', 'message') || 'Internal server error'
      Rails.logger.error "[WhatsApp API] Server error (#{response.code}): #{error_message}"
      raise NetworkError, 'WhatsApp API server error'
    else
      raise ApiError, "Unexpected response code: #{response.code}"
    end
  end

  def api_base_url
    'https://graph.facebook.com/v23.0'
  end

  def access_token
    @config['api_key']
  end
end
