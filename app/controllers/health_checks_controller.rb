# frozen_string_literal: true

# Health check controller for WhatsApp calling infrastructure
class HealthChecksController < ApplicationController
  skip_before_action :authenticate_user!, only: [:whatsapp_calling, :system], raise: false
  skip_before_action :verify_authenticity_token, only: [:whatsapp_calling, :system], raise: false

  # GET /health/whatsapp_calling
  def whatsapp_calling
    checks = {
      whatsapp_api: check_whatsapp_api,
      database: check_database,
      redis: check_redis
    }

    all_healthy = checks.values.all? { |check| check[:status] == 'healthy' }
    overall_status = all_healthy ? 'healthy' : 'degraded'

    render json: {
      status: overall_status,
      timestamp: Time.current.iso8601,
      checks: checks
    }, status: all_healthy ? :ok : :service_unavailable
  end

  # GET /health/system
  def system
    render json: {
      status: 'ok',
      timestamp: Time.current.iso8601,
      version: ENV['APP_VERSION'] || 'unknown'
    }, status: :ok
  end

  private

  def check_whatsapp_api
    return { status: 'disabled' } unless whatsapp_configured?

    # Check circuit breaker state
    circuit_breaker = Whatsapp::Calling::ApiAdapter.circuit_breaker

    {
      status: circuit_breaker.state == :closed ? 'healthy' : 'degraded',
      circuit_breaker_state: circuit_breaker.state
    }
  rescue StandardError => e
    {
      status: 'unknown',
      error: e.class.name
    }
  end

  def check_database
    start_time = Time.current
    ActiveRecord::Base.connection.execute('SELECT 1')
    response_time = ((Time.current - start_time) * 1000).round(2)

    {
      status: 'healthy',
      response_time_ms: response_time
    }
  rescue StandardError => e
    {
      status: 'unhealthy',
      error: e.class.name
    }
  end

  def check_redis
    start_time = Time.current
    Redis::Alfred.ping
    response_time = ((Time.current - start_time) * 1000).round(2)

    {
      status: 'healthy',
      response_time_ms: response_time
    }
  rescue StandardError => e
    {
      status: 'unhealthy',
      error: e.class.name
    }
  end

  def whatsapp_configured?
    true # WhatsApp is configured per channel
  end
end
