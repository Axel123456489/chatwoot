# frozen_string_literal: true

# Background job to deduplicate files for an account
class StorageDeduplicationJob < ApplicationJob
  queue_as :low

  # Use distributed lock to prevent duplicate deduplication jobs
  def perform(account_id)
    account = Account.find(account_id)
    lock_key = "storage_deduplication:#{account_id}"

    # Try to acquire lock
    locked = Rails.cache.write(lock_key, Time.current.to_i, unless_exist: true, expires_in: 2.hours)
    
    unless locked
      Rails.logger.info("[DeduplicationJob] Deduplication already in progress for account #{account_id}, skipping")
      return
    end

    begin
      # Write in_progress status to cache
      Rails.cache.write("storage_deduplication_status:#{account_id}", {
        status: 'in_progress',
        started_at: Time.current.iso8601,
        message: 'Deduplicating files...'
      }, expires_in: 2.hours)

      Rails.logger.info("[DeduplicationJob] Starting deduplication for account #{account_id}")
      start_time = Time.current

      service = AccountStorageService.new(account)
      
      # Run deduplication with progress logging
      result = service.deduplicate_files

      elapsed = (Time.current - start_time).round(2)
      Rails.logger.info("[DeduplicationJob] Completed deduplication in #{elapsed}s for account #{account_id}")
      Rails.logger.info("[DeduplicationJob] Results: #{result[:deduplicated_count]} files deduplicated, " \
                       "#{(result[:space_saved].to_f / 1.gigabyte).round(2)} GB saved")

      # Write results to cache
      cache_data = {
        status: 'completed',
        deduplicated_count: result[:deduplicated_count],
        space_saved: result[:space_saved],
        completed_at: Time.current.iso8601,
        duration_seconds: elapsed
      }
      
      Rails.cache.write("storage_deduplication_status:#{account_id}", cache_data, expires_in: 1.hour)
      Rails.logger.info("[DeduplicationJob] Results written to cache: storage_deduplication_status:#{account_id}")
    rescue StandardError => e
      Rails.logger.error("[DeduplicationJob] Error during deduplication for account #{account_id}: #{e.message}")
      Rails.logger.error(e.backtrace.join("\n"))

      # Write error to cache
      Rails.cache.write("storage_deduplication_status:#{account_id}", {
        status: 'error',
        error: e.message,
        completed_at: Time.current.iso8601
      }, expires_in: 1.hour)

      raise # Re-raise so Sidekiq knows it failed
    ensure
      # Always release the lock
      Rails.cache.delete(lock_key)
    end
  end
end
