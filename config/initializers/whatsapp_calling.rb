# frozen_string_literal: true

# Initialize WhatsApp Calling dependencies

# Autoload lib classes
Rails.application.config.autoload_paths += %W[
  #{Rails.root.join('app/lib')}
  #{Rails.root.join('app/repositories')}
]

# Eager load WhatsApp calling classes
Rails.application.config.to_prepare do
  # Load circuit breaker
  require_dependency 'circuit_breaker' unless defined?(CircuitBreaker)

  # Log initialization
  Rails.logger.info '[WhatsApp Calling] Initialization complete'

  # Setup circuit breaker for WhatsApp API
  Rails.logger.info '[WhatsApp Calling] Circuit breaker configured' if defined?(Whatsapp::Calling::ApiAdapter)

  # Setup cleanup job for stale calls
  if defined?(Sidekiq) && defined?(Whatsapp::Calling::Configuration) && Whatsapp::Calling::Configuration.daily_call_limit.positive?
    Rails.logger.info '[WhatsApp Calling] Stale call cleanup scheduled'
  end
end

# Setup scheduled jobs
# Skip during asset precompilation or when Redis is not available
if !(defined?(Rails::Console) || (File.basename($PROGRAM_NAME) == 'rake' && ARGV.include?('assets:precompile'))) && defined?(Sidekiq::Cron::Job)
  begin
    Sidekiq::Cron::Job.load_from_hash({
                                        # Commented out - jobs not implemented yet
                                        # 'cleanup_stale_calls' => {
                                        #   'class' => 'Whatsapp::Calling::CleanupStaleCallsJob',
                                        #   'cron' => '*/30 * * * *', # Every 30 minutes
                                        #   'queue' => 'low'
                                        # },
                                        # 'reset_daily_call_limits' => {
                                        #   'class' => 'Whatsapp::Calling::ResetDailyLimitsJob',
                                        #   'cron' => '0 0 * * *', # Daily at midnight
                                        #   'queue' => 'low'
                                        # },
                                        # 'process_call_recordings' => {
                                        #   'class' => 'Whatsapp::Calling::ProcessRecordingsJob',
                                        #   'cron' => '*/15 * * * *', # Every 15 minutes
                                        #   'queue' => 'low'
                                        # },
                                        'cleanup_old_recordings' => {
                                          'class' => 'Whatsapp::Calling::CleanupRecordingsJob',
                                          'cron' => '0 2 * * *', # Daily at 2 AM
                                          'queue' => 'low'
                                        }
                                      })
  rescue RedisClient::CannotConnectError, Redis::CannotConnectError => e
    Rails.logger.warn "[WhatsApp Calling] Skipping Sidekiq Cron job registration: Redis not available (#{e.message})"
  end
end
