# frozen_string_literal: true

# Background job to cleanup orphan blobs for an account
class StorageCleanupJob < ApplicationJob
  queue_as :low

  LOCK_TTL = 2.hours

  def perform(account_id)
    account = Account.find(account_id)
    lock_key = "storage_cleanup:#{account_id}"
    status_key = "storage_cleanup_status:#{account_id}"

    # Try to acquire lock
    locked = Rails.cache.write(lock_key, Time.current.to_i, unless_exist: true, expires_in: LOCK_TTL)

    unless locked
      existing_status = Rails.cache.read(status_key)
      stale = stale_lock?(lock_key, existing_status)

      if stale
        Rails.logger.warn("[CleanupJob] Stale lock detected for account #{account_id}, force-releasing and retrying")
        Rails.cache.delete(lock_key)
        locked = Rails.cache.write(lock_key, Time.current.to_i, unless_exist: true, expires_in: LOCK_TTL)
      end

      unless locked
        Rails.logger.info("[CleanupJob] Cleanup already in progress for account #{account_id}, skipping")
        return
      end
    end

    begin
      Rails.cache.write(status_key, {
        status: 'in_progress',
        started_at: Time.current.iso8601,
        message: 'Cleaning orphan blobs...'
      }, expires_in: LOCK_TTL)

      Rails.logger.info("[CleanupJob] Starting orphan cleanup for account #{account_id}")
      start_time = Time.current

      service = AccountStorageService.new(account)
      result = service.cleanup_orphan_blobs

      elapsed = (Time.current - start_time).round(2)
      Rails.logger.info("[CleanupJob] Completed cleanup in #{elapsed}s for account #{account_id}")
      Rails.logger.info("[CleanupJob] Results: #{result[:cleaned_count]} orphan blobs removed, " \
                        "#{(result[:space_freed].to_f / 1.gigabyte).round(2)} GB freed")

      cache_data = {
        status: 'completed',
        cleaned_count: result[:cleaned_count],
        space_freed: result[:space_freed],
        completed_at: Time.current.iso8601,
        duration_seconds: elapsed
      }

      Rails.cache.write(status_key, cache_data, expires_in: 1.hour)
      Rails.logger.info("[CleanupJob] Results written to cache: #{status_key}")
    rescue Sidekiq::Shutdown => e
      Rails.logger.warn("[CleanupJob] Sidekiq shutdown during cleanup for account #{account_id}")
      Rails.cache.write(status_key, {
        status: 'interrupted',
        error: 'Sidekiq was restarted while the job was running. Please start again.',
        interrupted_at: Time.current.iso8601
      }, expires_in: 24.hours)
      raise
    rescue StandardError => e
      Rails.logger.error("[CleanupJob] Error during cleanup for account #{account_id}: #{e.message}")
      Rails.logger.error(e.backtrace.join("\n"))

      Rails.cache.write(status_key, {
        status: 'error',
        error: e.message,
        completed_at: Time.current.iso8601
      }, expires_in: 1.hour)

      raise
    ensure
      Rails.cache.delete(lock_key)
    end
  end

  private

  def stale_lock?(lock_key, existing_status)
    return false unless existing_status
    return false unless (existing_status[:status] || existing_status['status']) == 'in_progress'

    lock_value = Rails.cache.read(lock_key)
    return true unless lock_value

    locked_at = Time.at(lock_value.to_i)
    Time.current - locked_at > LOCK_TTL
  rescue StandardError
    false
  end
end
