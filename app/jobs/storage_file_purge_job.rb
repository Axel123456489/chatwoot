# frozen_string_literal: true

# Asynchronously deletes physical storage files (S3/GCS/disk) for blob keys
# that were enqueued by the deduplication or cleanup process.
#
# This is intentionally separate from StorageDeduplicationJob so that:
#   - Deduplication is pure DB work (fast, ~300 blobs/sec)
#   - S3 deletions happen in the background without blocking any UI feedback
#
# Keys are stored in a Redis list: storage_purge_queue:{account_id}
class StorageFilePurgeJob < ApplicationJob
  queue_as :low

  LOCK_TTL       = 8.hours
  BATCH_SIZE     = 1_000  # keys per iteration
  STATUS_KEY     = 'storage_purge_status:%<account_id>s'
  QUEUE_REDIS_KEY = AccountStorageService::PURGE_QUEUE_REDIS_KEY

  def perform(account_id)
    account   = Account.find(account_id)
    lock_key  = "storage_file_purge:#{account_id}"
    status_key = format(STATUS_KEY, account_id: account_id)
    queue_key  = format(QUEUE_REDIS_KEY, account_id: account_id)

    locked = Rails.cache.write(lock_key, Time.current.to_i, unless_exist: true, expires_in: LOCK_TTL)
    unless locked
      Rails.logger.info("[PurgeJob] Already running for account #{account_id}, skipping")
      return
    end

    begin
      total_pending = Sidekiq.redis { |r| r.llen(queue_key) }.to_i
      Rails.logger.info("[PurgeJob] Starting storage purge for account #{account_id}: ~#{total_pending} keys")

      Rails.cache.write(status_key, {
        status: 'in_progress',
        started_at: Time.current.iso8601,
        total_keys: total_pending,
        deleted_keys: 0
      }, expires_in: LOCK_TTL)

      service       = AccountStorageService.new(account)
      deleted_total = 0
      start_time    = Time.current

      loop do
        # Atomically pop up to BATCH_SIZE keys from the front of the list
        keys = Sidekiq.redis { |r| r.lpop(queue_key, BATCH_SIZE) }
        break if keys.nil? || keys.empty?

        service.purge_storage_keys(keys)
        deleted_total += keys.size

        remaining = Sidekiq.redis { |r| r.llen(queue_key) }.to_i
        Rails.logger.info("[PurgeJob] Deleted #{deleted_total} keys, #{remaining} remaining")

        Rails.cache.write(status_key, {
          status: 'in_progress',
          started_at: Time.current.iso8601,
          total_keys: total_pending,
          deleted_keys: deleted_total,
          remaining_keys: remaining
        }, expires_in: LOCK_TTL)
      end

      elapsed = (Time.current - start_time).round(2)
      Rails.logger.info("[PurgeJob] Completed: #{deleted_total} keys deleted in #{elapsed}s for account #{account_id}")

      Rails.cache.write(status_key, {
        status: 'completed',
        deleted_keys: deleted_total,
        completed_at: Time.current.iso8601,
        duration_seconds: elapsed
      }, expires_in: 24.hours)
    rescue Sidekiq::Shutdown
      Rails.logger.warn("[PurgeJob] Sidekiq shutdown during purge for account #{account_id}")
      Rails.cache.write(status_key, {
        status: 'interrupted',
        error: 'Sidekiq was restarted. Re-enqueue StorageFilePurgeJob to continue.',
        interrupted_at: Time.current.iso8601
      }, expires_in: 24.hours)
      raise
    rescue StandardError => e
      Rails.logger.error("[PurgeJob] Error for account #{account_id}: #{e.message}")
      Rails.cache.write(status_key, {
        status: 'error',
        error: e.message,
        completed_at: Time.current.iso8601
      }, expires_in: 24.hours)
      raise
    ensure
      Rails.cache.delete(lock_key)
    end
  end
end
