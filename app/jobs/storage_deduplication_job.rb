# frozen_string_literal: true

# Background job to deduplicate files for an account
class StorageDeduplicationJob < ApplicationJob
  queue_as :low

  # Lock TTL must match the expires_in used when writing the lock
  LOCK_TTL = 4.hours

  # Use distributed lock to prevent duplicate deduplication jobs
  # @param account_id [Integer] The account ID
  # @param batch_size [Integer] Checksums per batch (default: 500)
  # @param max_checksums [Integer] Max checksums to process, nil = all (default: nil)
  def perform(account_id, batch_size: 500, max_checksums: nil)
    account = Account.find(account_id)
    lock_key = "storage_deduplication:#{account_id}"
    status_key = "storage_deduplication_status:#{account_id}"

    # Try to acquire lock
    locked = Rails.cache.write(lock_key, Time.current.to_i, unless_exist: true, expires_in: LOCK_TTL)

    unless locked
      # Detect stale lock: status says in_progress but the lock was never cleaned
      # (e.g. previous job was killed with SIGKILL and ensure did not run)
      existing_status = Rails.cache.read(status_key)
      stale = stale_lock?(lock_key, existing_status)

      if stale
        Rails.logger.warn("[DeduplicationJob] Stale lock detected for account #{account_id}, force-releasing and retrying")
        Rails.cache.delete(lock_key)
        locked = Rails.cache.write(lock_key, Time.current.to_i, unless_exist: true, expires_in: LOCK_TTL)
      end

      unless locked
        Rails.logger.info("[DeduplicationJob] Deduplication already in progress for account #{account_id}, skipping")
        return
      end
    end

    begin
      # Write in_progress status to cache
      Rails.cache.write(status_key, {
                          status: 'in_progress',
                          started_at: Time.current.iso8601,
                          message: 'Deduplicating files...',
                          batch_size: batch_size,
                          max_checksums: max_checksums
                        }, expires_in: LOCK_TTL)

      Rails.logger.info(
        "[DeduplicationJob] Starting deduplication for account #{account_id} " \
        "(batch_size: #{batch_size}, max: #{max_checksums || 'all'})"
      )
      start_time = Time.current

      service = AccountStorageService.new(account)

      # Run deduplication with batching
      result = service.deduplicate_files(batch_size: batch_size, max_checksums: max_checksums)

      elapsed = (Time.current - start_time).round(2)

      if result[:cancelled]
        Rails.logger.info("[DeduplicationJob] Deduplication cancelled for account #{account_id} after #{result[:processed_checksums]} checksums")
        Rails.cache.write(status_key, {
                            status: 'cancelled',
                            deduplicated_count: result[:deduplicated_count],
                            space_saved: result[:space_saved],
                            processed_checksums: result[:processed_checksums],
                            cancelled_at: Time.current.iso8601,
                            duration_seconds: elapsed,
                            message: 'Cancelled by user'
                          }, expires_in: 24.hours)
        return
      end

      Rails.logger.info("[DeduplicationJob] Completed deduplication in #{elapsed}s for account #{account_id}")
      Rails.logger.info("[DeduplicationJob] Results: #{result[:deduplicated_count]} files deduplicated, " \
                        "#{(result[:space_saved].to_f / 1.gigabyte).round(2)} GB saved, " \
                        "#{result[:processed_checksums]} checksums processed")

      # Check how many storage keys are pending physical deletion
      pending_purge = service.pending_purge_count

      cache_data = {
        status: 'completed',
        deduplicated_count: result[:deduplicated_count],
        space_saved: result[:space_saved],
        processed_checksums: result[:processed_checksums],
        completed_at: Time.current.iso8601,
        duration_seconds: elapsed,
        purge_queued: pending_purge.positive?,
        pending_purge_keys: pending_purge
      }

      Rails.cache.write(status_key, cache_data, expires_in: 24.hours)
      Rails.logger.info("[DeduplicationJob] Results written to cache: #{status_key}")

      # Invalidate stale storage analysis cache so next UI load shows fresh data
      Rails.cache.delete("storage_analysis:#{account_id}")
      Rails.cache.delete("storage_analysis:#{account_id}:status")

      # Fire async storage purge job if there are physical files to delete
      if pending_purge.positive?
        Rails.logger.info("[DeduplicationJob] Enqueueing StorageFilePurgeJob for #{pending_purge} storage keys")
        StorageFilePurgeJob.perform_later(account_id)
      end
    rescue Sidekiq::Shutdown
      # Sidekiq is shutting down (SIGTERM): ensure will still run and release the lock,
      # but we update status so the UI shows the job can be retried.
      Rails.logger.warn("[DeduplicationJob] Sidekiq shutdown during deduplication for account #{account_id}")
      Rails.cache.write(status_key, {
                          status: 'interrupted',
                          error: 'Sidekiq was restarted while the job was running. Please start again.',
                          interrupted_at: Time.current.iso8601
                        }, expires_in: 24.hours)
      raise
    rescue StandardError => e
      Rails.logger.error("[DeduplicationJob] Error during deduplication for account #{account_id}: #{e.message}")
      Rails.logger.error(e.backtrace.join("\n"))

      Rails.cache.write(status_key, {
                          status: 'error',
                          error: e.message,
                          completed_at: Time.current.iso8601
                        }, expires_in: 24.hours)

      raise
    ensure
      Rails.cache.delete(lock_key)
      Rails.cache.delete("storage_deduplication_cancel:#{account_id}")
    end
  end

  private

  # A lock is stale when the status says in_progress but the lock timestamp
  # shows the job started longer ago than the lock TTL (it should have expired),
  # OR the lock value cannot be parsed (corrupted entry).
  def stale_lock?(lock_key, existing_status)
    return false unless existing_status
    return false unless (existing_status[:status] || existing_status['status']) == 'in_progress'

    lock_value = Rails.cache.read(lock_key)
    return true unless lock_value # lock disappeared between write and re-read

    locked_at = Time.zone.at(lock_value.to_i)
    Time.current - locked_at > LOCK_TTL
  rescue StandardError
    false
  end
end
