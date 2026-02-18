# frozen_string_literal: true

# Service for adding observability metrics to WhatsApp calls
class Whatsapp::Calling::MetricsService
  class << self
    # Track call initiation
    def track_call_initiated(direction:, inbox_id:)
      increment_counter('whatsapp.calls.initiated', tags: ["direction:#{direction}", "inbox:#{inbox_id}"])
    end

    # Track call state changes
    def track_state_change(from_state:, to_state:, call_id:)
      increment_counter('whatsapp.calls.state_change', tags: [
                          "from:#{from_state}",
                          "to:#{to_state}"
                        ])
    end

    # Track call duration
    def track_call_duration(duration_seconds:, direction:)
      record_timing('whatsapp.calls.duration', duration_seconds * 1000, tags: ["direction:#{direction}"])
    end

    # Track call success/failure
    def track_call_outcome(outcome:, direction:)
      increment_counter('whatsapp.calls.outcome', tags: [
                          "outcome:#{outcome}",
                          "direction:#{direction}"
                        ])
    end

    # Track API errors
    def track_api_error(error_type:, operation:)
      increment_counter('whatsapp.calls.api_errors', tags: [
                          "error_type:#{error_type}",
                          "operation:#{operation}"
                        ])
    end

    # Track WebRTC setup time
    def track_setup_time(duration_ms:)
      record_timing('whatsapp.calls.setup_time', duration_ms)
    end

    # Track ICE candidate exchanges
    def track_ice_candidates(count:, type:)
      record_gauge('whatsapp.calls.ice_candidates', count, tags: ["type:#{type}"])
    end

    # Track call quality metrics
    def track_quality_metric(metric_name:, value:)
      record_gauge("whatsapp.calls.quality.#{metric_name}", value)
    end

    private

    def increment_counter(metric, tags: [])
      return unless metrics_enabled?

      # StatsD format (if using DataDog, StatsD, etc.)
      StatsD.increment(metric, tags: tags) if defined?(StatsD)

      # Log for debugging
      Rails.logger.debug { "[Metrics] #{metric} +1 #{tags.join(', ')}" }
    end

    def record_timing(metric, value, tags: [])
      return unless metrics_enabled?

      StatsD.timing(metric, value, tags: tags) if defined?(StatsD)

      Rails.logger.debug { "[Metrics] #{metric} #{value}ms #{tags.join(', ')}" }
    end

    def record_gauge(metric, value, tags: [])
      return unless metrics_enabled?

      StatsD.gauge(metric, value, tags: tags) if defined?(StatsD)

      Rails.logger.debug { "[Metrics] #{metric} = #{value} #{tags.join(', ')}" }
    end

    def metrics_enabled?
      ENV.fetch('METRICS_ENABLED', 'true') == 'true'
    end
  end
end
