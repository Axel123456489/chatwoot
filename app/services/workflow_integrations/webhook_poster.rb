# frozen_string_literal: true

# Webhook HTTP poster with retry logic
# Reusable for all workflow integrations (N8n, Make, Zapier, etc.)
module WorkflowIntegrations
  class WebhookPoster
    MAX_RETRIES = 3
    BASE_BACKOFF = 0.25
    TIMEOUT = 8

    attr_reader :url, :payload

    def initialize(url, payload)
      @url = url
      @payload = payload
    end

    def execute
      attempts = 0

      begin
        started_at = Time.current
        response = http_post
        duration_ms = ((Time.current - started_at) * 1000).round

        if success?(response)
          log_success(response.code, duration_ms)
          return response
        end

        if retryable?(response)
          raise RetryableError, "HTTP #{response.code}"
        else
          raise NonRetryableError, "HTTP #{response.code}"
        end
      rescue RetryableError => e
        attempts += 1
        if attempts < MAX_RETRIES
          sleep_time = backoff_with_jitter(attempts)
          log_retry(attempts, sleep_time, e.message)
          sleep(sleep_time)
          retry
        end
        log_error(attempts, e.message)
        raise
      rescue StandardError => e
        log_error(attempts, e.message)
        raise
      end
    end

    private

    def http_post
      HTTParty.post(url, {
                      headers: { 'Content-Type' => 'application/json' },
                      body: payload.to_json,
                      timeout: TIMEOUT
                    })
    end

    def success?(response)
      response.code.between?(200, 299)
    end

    def retryable?(response)
      code = response.code.to_i
      return true if code.zero?
      return true if [408, 429].include?(code)
      return true if code.between?(500, 599)

      false
    end

    def backoff_with_jitter(attempt)
      base = BASE_BACKOFF * (2**(attempt - 1))
      jitter = rand(0.0..(base / 2.0))
      (base + jitter).round(3)
    end

    def safe_url
      uri = URI.parse(url)
      port_part = standard_port?(uri) ? '' : ":#{uri.port}"
      "#{uri.scheme}://#{uri.host}#{port_part}#{uri.path}"
    rescue URI::InvalidURIError
      '<invalid-url>'
    end

    def standard_port?(uri)
      (uri.scheme == 'https' && uri.port == 443) || (uri.scheme == 'http' && uri.port == 80)
    end

    def log_success(code, duration_ms)
      Rails.logger.info("[WebhookPoster] Success url=#{safe_url} code=#{code} dur_ms=#{duration_ms}")
    end

    def log_retry(attempt, sleep_time, error)
      Rails.logger.info("[WebhookPoster] Retry attempt=#{attempt} sleep=#{sleep_time}s url=#{safe_url} error=#{error}")
    end

    def log_error(attempts, error)
      Rails.logger.error("[WebhookPoster] Failed attempts=#{attempts} url=#{safe_url} error=#{error}")
    end

    class RetryableError < StandardError; end
    class NonRetryableError < StandardError; end
  end
end
