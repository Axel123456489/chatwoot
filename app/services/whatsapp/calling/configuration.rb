# frozen_string_literal: true

# Centralized configuration for WhatsApp Calling functionality
class Whatsapp::Calling::Configuration
  class << self
    # Call limits
    def daily_call_limit
      ENV.fetch('WHATSAPP_DAILY_CALL_LIMIT', 10).to_i
    end

    def max_call_duration
      ENV.fetch('WHATSAPP_MAX_CALL_DURATION', 3600).to_i # 1 hour default
    end

    def call_timeout
      ENV.fetch('WHATSAPP_CALL_TIMEOUT', 300).to_i # 5 minutes default
    end

    # SDP configuration
    def sdp_answer_wait_time
      ENV.fetch('WHATSAPP_SDP_WAIT_TIME', 30).to_i # 30 seconds
    end

    def ice_gathering_timeout
      ENV.fetch('ICE_GATHERING_TIMEOUT', 3).to_i # 3 seconds
    end

    # Polling configuration
    def polling_initial_interval
      ENV.fetch('WHATSAPP_POLLING_INITIAL', 1000).to_i # 1 second
    end

    def polling_max_interval
      ENV.fetch('WHATSAPP_POLLING_MAX', 2000).to_i # 2 seconds
    end

    def polling_max_attempts
      ENV.fetch('WHATSAPP_POLLING_MAX_ATTEMPTS', 30).to_i
    end

    # Media server configuration
    def media_server_enabled?
      get_config('MEDIA_SERVER_ENABLED', 'true') == 'true'
    end

    def media_server_public_host
      get_config('MEDIA_SERVER_PUBLIC_HOST', nil) ||
        MediaServerConfig.media_server_config['public_host']
    end

    def media_server_public_port
      get_config('MEDIA_SERVER_PUBLIC_PORT', '50000').to_i
    end

    # Recording configuration
    def recording_enabled?
      # Check installation config first, then ENV
      get_config('CALL_RECORDING_ENABLED', 'false') == 'true'
    end

    def recording_path
      get_config('CALL_RECORDING_PATH', Rails.root.join('tmp/recordings').to_s)
    end

    # Circuit breaker configuration
    def circuit_breaker_failure_threshold
      ENV.fetch('CIRCUIT_BREAKER_FAILURE_THRESHOLD', 5).to_i
    end

    def circuit_breaker_timeout
      ENV.fetch('CIRCUIT_BREAKER_TIMEOUT', 60).to_i
    end

    def circuit_breaker_success_threshold
      ENV.fetch('CIRCUIT_BREAKER_SUCCESS_THRESHOLD', 2).to_i
    end

    # Retry configuration
    def max_retries
      ENV.fetch('WHATSAPP_API_MAX_RETRIES', 3).to_i
    end

    def retry_delay
      ENV.fetch('WHATSAPP_API_RETRY_DELAY', 1).to_i # seconds
    end

    # Feature flags
    def trickle_ice_enabled?
      ENV.fetch('TRICKLE_ICE_ENABLED', 'false') == 'true'
    end

    def call_quality_monitoring_enabled?
      ENV.fetch('CALL_QUALITY_MONITORING', 'true') == 'true'
    end

    # Logging
    def verbose_logging?
      ENV.fetch('WHATSAPP_CALLS_VERBOSE_LOGGING', 'false') == 'true'
    end

    def log_level
      ENV.fetch('WHATSAPP_CALLS_LOG_LEVEL', 'info').to_sym
    end

    private

    # Get config from InstallationConfig with fallback to ENV
    def get_config(key, default = nil)
      # Try InstallationConfig first
      installation_config = InstallationConfig.find_by(name: key)
      return installation_config.value if installation_config&.value.present?

      # Fallback to ENV
      ENV.fetch(key, default)
    end
  end
end
