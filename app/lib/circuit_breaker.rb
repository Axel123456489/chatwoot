# frozen_string_literal: true

# Simple Circuit Breaker implementation for external service calls
# Prevents cascading failures by stopping requests when service is failing
class CircuitBreaker
  STATES = %i[closed open half_open].freeze

  attr_reader :failure_threshold, :timeout, :success_threshold, :state

  def initialize(service_name, failure_threshold: 5, timeout: 60, success_threshold: 2)
    @service_name = service_name
    @failure_threshold = failure_threshold
    @timeout = timeout
    @success_threshold = success_threshold
    @state = :closed
    @failure_count = 0
    @success_count = 0
    @last_failure_time = nil
  end

  def call
    case @state
    when :open
      raise CircuitBreakerOpenError, "Circuit breaker is OPEN for #{@service_name}" unless circuit_open_timeout_expired?

      transition_to(:half_open)

    end

    begin
      result = yield
      on_success
      result
    rescue StandardError
      on_failure
      raise
    end
  end

  private

  def on_success
    @failure_count = 0

    return unless @state == :half_open

    @success_count += 1
    transition_to(:closed) if @success_count >= @success_threshold
  end

  def on_failure
    @failure_count += 1
    @last_failure_time = Time.current
    @success_count = 0

    return unless @failure_count >= @failure_threshold

    transition_to(:open)
  end

  def circuit_open_timeout_expired?
    return false unless @last_failure_time

    Time.current >= (@last_failure_time + @timeout)
  end

  def transition_to(new_state)
    old_state = @state
    @state = new_state

    Rails.logger.info "[CircuitBreaker] #{@service_name}: #{old_state} -> #{new_state}"

    return unless new_state == :half_open

    @success_count = 0
  end

  class CircuitBreakerOpenError < StandardError; end
end
