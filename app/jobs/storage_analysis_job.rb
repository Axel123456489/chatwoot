# frozen_string_literal: true

# Background job to analyze account storage asynchronously
class StorageAnalysisJob < ApplicationJob
  queue_as :low

  # Execute storage analysis in background
  # Results are cached for 2 hours
  def perform(account_id)
    account = Account.find(account_id)
    cache_key = "storage_analysis:#{account_id}"
    lock_key = "#{cache_key}:lock"
    
    # Try to acquire lock to prevent duplicate analysis
    lock_acquired = Rails.cache.write(lock_key, true, unless_exist: true, expires_in: 90.minutes)
    
    unless lock_acquired
      Rails.logger.warn("[StorageAnalysisJob] Analysis already in progress for account #{account_id}, skipping")
      return
    end
    
    Rails.logger.info("[StorageAnalysisJob] Starting analysis for account #{account_id}")
    start_time = Time.current

    # Mark analysis as in progress
    Rails.cache.write("#{cache_key}:status", 'in_progress', expires_in: 2.hours)
    Rails.cache.write("#{cache_key}:started_at", start_time.to_s, expires_in: 2.hours)

    begin
      service = AccountStorageService.new(account)
      
      # Log if it's a large account
      is_large = service.large_account?
      Rails.logger.info("[StorageAnalysisJob] Account #{account_id} is #{is_large ? 'LARGE' : 'small'} - using #{is_large ? '60min' : '10min'} timeout")
      
      # Execute analysis with progress reporting
      Rails.logger.info("[StorageAnalysisJob] Step 1/5: Analyzing overview...")
      analysis = service.analyze
      
      duration = Time.current - start_time
      
      # Cache results for 2 hours (same as status TTL)
      result = {
        overview: analysis[:overview],
        by_content_type: analysis[:by_content_type],
        orphan_blobs: analysis[:orphan_blobs],
        duplicates: analysis[:duplicates],
        by_source: analysis[:by_source],
        analysis_duration_seconds: duration.round(2),
        analyzed_at: Time.current.iso8601,
        is_large_account: is_large
      }
      
      Rails.cache.write(cache_key, result, expires_in: 2.hours)
      Rails.cache.write("#{cache_key}:status", 'completed', expires_in: 2.hours)
      Rails.cache.delete("#{cache_key}:started_at")
      Rails.cache.delete(lock_key) # Release lock
      
      Rails.logger.info("[StorageAnalysisJob] Completed analysis in #{duration.round(2)}s for account #{account_id}")
      Rails.logger.info("[StorageAnalysisJob] Results: #{result[:overview][:total_blobs]} blobs, #{(result[:overview][:total_size].to_f / 1.gigabyte).round(2)} GB")
      Rails.logger.info("[StorageAnalysisJob] Cache written to: #{cache_key}")
      
    rescue ActiveRecord::StatementInvalid => e
      Rails.cache.delete(lock_key) # Release lock on error
      if e.message.include?('statement timeout')
        Rails.logger.error("[StorageAnalysisJob] Timeout for account #{account_id}: #{e.message}")
        Rails.cache.write("#{cache_key}:status", 'timeout', expires_in: 2.hours)
        Rails.cache.write("#{cache_key}:error", 'Analysis timed out. Contact support.', expires_in: 2.hours)
      else
        Rails.logger.error("[StorageAnalysisJob] Error for account #{account_id}: #{e.message}")
        Rails.cache.write("#{cache_key}:status", 'failed', expires_in: 2.hours)
        Rails.cache.write("#{cache_key}:error", e.message, expires_in: 2.hours)
      end
      raise
    rescue StandardError => e
      Rails.cache.delete(lock_key) # Release lock on error
      Rails.logger.error("[StorageAnalysisJob] Error for account #{account_id}: #{e.message}\n#{e.backtrace.join("\n")}")
      Rails.cache.write("#{cache_key}:status", 'failed', expires_in: 2.hours)
      Rails.cache.write("#{cache_key}:error", e.message, expires_in: 2.hours)
      raise
    end
  end
end
