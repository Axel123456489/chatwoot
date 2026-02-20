# frozen_string_literal: true

# Background job to cleanup orphan blobs for an account
class StorageCleanupJob < ApplicationJob
  queue_as :low

  def perform(account_id)
    account = Account.find(account_id)
    lock_key = "storage_cleanup:#{account_id}"

    # Try to acquire lock
    locked = Rails.cache.write(lock_key, Time.current.to_i, unless_exist: true, expires_in: 2.hours)
    
    unless locked
      Rails.logger.info("[CleanupJob] Cleanup already in progress for account #{account_id}, skipping")
      return
    end

    begin
      # Write in_progress status to cache
      Rails.cache.write("storage_cleanup_status:#{account_id}", {
        status: 'in_progress',
        started_at: Time.current.iso8601,
        message: 'Cleaning orphan blobs...'
      }, expires_in: 2.hours)

      Rails.logger.info("[CleanupJob] Starting orphan cleanup for account #{account_id}")
      start_time = Time.current

      service = AccountStorageService.new(account)
      result = service.cleanup_orphan_blobs

      elapsed = (Time.current - start_time).round(2)
      Rails.logger.info("[CleanupJob] Completed cleanup in #{elapsed}s for account #{account_id}")
      Rails.logger.info("[CleanupJob] Results: #{result[:cleaned_count]} orphan blobs removed, " \
                       "#{(result[:space_freed].to_f / 1.gigabyte).round(2)} GB freed")

      # Write results to cache
      cache_data = {
        status: 'completed',
        cleaned_count: result[:cleaned_count],
        space_freed: result[:space_freed],
        completed_at: Time.current.iso8601,
        duration_seconds: elapsed
      }
      
      Rails.cache.write("storage_cleanup_status:#{account_id}", cache_data, expires_in: 1.hour)
      Rails.logger.info("[CleanupJob] Results written to cache: storage_cleanup_status:#{account_id}")
    rescue StandardError => e
      Rails.logger.error("[CleanupJob] Error during cleanup for account #{account_id}: #{e.message}")
      Rails.logger.error(e.backtrace.join("\n"))

      # Write error to cache
      Rails.cache.write("storage_cleanup_status:#{account_id}", {
        status: 'error',
        error: e.message,
        completed_at: Time.current.iso8601
      }, expires_in: 1.hour)

      raise
    ensure
      # Always release the lock
      Rails.cache.delete(lock_key)
    end
  end
end
