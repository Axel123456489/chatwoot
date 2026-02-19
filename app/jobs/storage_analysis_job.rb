# frozen_string_literal: true

# Background job to analyze account storage asynchronously
class StorageAnalysisJob < ApplicationJob
  queue_as :low_priority

  # Execute storage analysis in background
  # Results are cached for 1 hour
  def perform(account_id)
    account = Account.find(account_id)
    
    Rails.logger.info("[StorageAnalysisJob] Starting analysis for account #{account_id}")
    start_time = Time.current

    # Mark analysis as in progress
    cache_key = "storage_analysis:#{account_id}"
    Rails.cache.write("#{cache_key}:status", 'in_progress', expires_in: 2.hours)

    begin
      service = AccountStorageService.new(account)
      analysis = service.analyze
      
      duration = Time.current - start_time
      
      # Cache results for 1 hour
      result = {
        overview: analysis[:overview],
        by_content_type: analysis[:by_content_type],
        orphan_blobs: analysis[:orphan_blobs],
        duplicates: analysis[:duplicates],
        by_source: analysis[:by_source],
        analysis_duration_seconds: duration.round(2),
        analyzed_at: Time.current.iso8601
      }
      
      Rails.cache.write(cache_key, result, expires_in: 1.hour)
      Rails.cache.write("#{cache_key}:status", 'completed', expires_in: 2.hours)
      
      Rails.logger.info("[StorageAnalysisJob] Completed analysis in #{duration.round(2)}s for account #{account_id}")
      
    rescue ActiveRecord::StatementInvalid => e
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
      Rails.logger.error("[StorageAnalysisJob] Error for account #{account_id}: #{e.message}\n#{e.backtrace.join("\n")}")
      Rails.cache.write("#{cache_key}:status", 'failed', expires_in: 2.hours)
      Rails.cache.write("#{cache_key}:error", e.message, expires_in: 2.hours)
      raise
    end
  end
end
