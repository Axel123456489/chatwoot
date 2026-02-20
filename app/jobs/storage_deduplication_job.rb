# frozen_string_literal: true

# Background job to deduplicate files for an account
class StorageDeduplicationJob < ApplicationJob
  queue_as :low

  # Use distributed lock to prevent duplicate deduplication jobs
  # @param account_id [Integer] The account ID
  # @param batch_size [Integer] Number of checksums per batch (default: 100)
  # @param max_checksums [Integer] Max checksums to process, nil = all (default: nil)
  def perform(account_id, batch_size: 100, max_checksums: nil)
    account = Account.find(account_id)
    lock_key = "storage_deduplication:#{account_id}"

    # Try to acquire lock
    locked = Rails.cache.write(lock_key, Time.current.to_i, unless_exist: true, expires_in: 4.hours)
    
    unless locked
      Rails.logger.info("[DeduplicationJob] Deduplication already in progress for account #{account_id}, skipping")
      return
    end

    begin
      # Write in_progress status to cache
      Rails.cache.write("storage_deduplication_status:#{account_id}", {
        status: 'in_progress',
        started_at: Time.current.iso8601,
        message: 'Deduplicating files...',
        batch_size: batch_size,
        max_checksums: max_checksums
      }, expires_in: 4.hours)

      Rails.logger.info("[DeduplicationJob] Starting deduplication for account #{account_id} (batch_size: #{batch_size}, max: #{max_checksums || 'all'})")
      start_time = Time.current

      service = AccountStorageService.new(account)
      
      # Run deduplication with batching
      result = service.deduplicate_files(batch_size: batch_size, max_checksums: max_checksums)

      elapsed = (Time.current - start_time).round(2)
      Rails.logger.info("[DeduplicationJob] Completed deduplication in #{elapsed}s for account #{account_id}")
      Rails.logger.info("[DeduplicationJob] Results: #{result[:deduplicated_count]} files deduplicated, " \
                       "#{(result[:space_saved].to_f / 1.gigabyte).round(2)} GB saved, " \
                       "#{result[:processed_checksums]} checksums processed")

      # Write results to cache
      cache_data = {
        status: 'completed',
        deduplicated_count: result[:deduplicated_count],
        space_saved: result[:space_saved],
        processed_checksums: result[:processed_checksums],
        completed_at: Time.current.iso8601,
        duration_seconds: elapsed
      }
      
      Rails.cache.write("storage_deduplication_status:#{account_id}", cache_data, expires_in: 24.hours)
      Rails.logger.info("[DeduplicationJob] Results written to cache: storage_deduplication_status:#{account_id}")
    rescue StandardError => e
      Rails.logger.error("[DeduplicationJob] Error during deduplication for account #{account_id}: #{e.message}")
      Rails.logger.error(e.backtrace.join("\n"))

      # Write error to cache
      Rails.cache.write("storage_deduplication_status:#{account_id}", {
        status: 'error',
        error: e.message,
        completed_at: Time.current.iso8601
      }, expires_in: 24.hours)

      raise # Re-raise so Sidekiq knows it failed
    ensure
      # Always release the lock
      Rails.cache.delete(lock_key)
    end
  end
end
