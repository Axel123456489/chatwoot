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
