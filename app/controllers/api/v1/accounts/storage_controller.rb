# frozen_string_literal: true

class Api::V1::Accounts::StorageController < Api::V1::Accounts::BaseController
  before_action :check_authorization

  # GET /api/v1/accounts/:account_id/storage/analyze
  # Analyze storage usage for the account
  # Options:
  #   ?async=true - Run analysis in background (recommended for large accounts)
  #   ?force=true - Force new analysis (ignore cache)
  def analyze
    cache_key = "storage_analysis:#{Current.account.id}"
    force_refresh = params[:force] == 'true'
    async_mode = params[:async] == 'true'

    # Check if analysis is already in progress
    status = Rails.cache.read("#{cache_key}:status")
    
    if status == 'in_progress'
      return render json: {
        status: 'in_progress',
        message: 'Analysis is currently running. Check status or wait for completion.'
      }, status: :accepted
    end

    # Return cached results if available and not forcing refresh
    unless force_refresh
      cached = Rails.cache.read(cache_key)
      if cached.present?
        Rails.logger.info("[Storage] Returning cached analysis for account #{Current.account.id}")
        return render json: cached.merge(cached: true)
      end
    end

    # Run async if requested or if account is large
    if async_mode || should_use_async?
      Rails.logger.info("[Storage] Queuing async analysis for account #{Current.account.id}")
      StorageAnalysisJob.perform_later(Current.account.id)
      
      return render json: {
        status: 'queued',
        message: 'Analysis started in background. Use /storage/status to check progress.',
        check_status_url: api_v1_account_storage_status_url(Current.account)
      }, status: :accepted
    end

    # Run synchronously for small accounts
    Rails.logger.info("[Storage] Starting sync analysis for account #{Current.account.id}")
    start_time = Time.current

    service = AccountStorageService.new(Current.account)
    analysis = service.analyze

    duration = Time.current - start_time
    Rails.logger.info("[Storage] Analysis completed in #{duration.round(2)}s for account #{Current.account.id}")

    result = {
      overview: analysis[:overview],
      by_content_type: analysis[:by_content_type],
      orphan_blobs: analysis[:orphan_blobs],
      duplicates: analysis[:duplicates],
      by_source: analysis[:by_source],
      analysis_duration_seconds: duration.round(2),
      analyzed_at: Time.current.iso8601
    }

    # Cache for 1 hour
    Rails.cache.write(cache_key, result, expires_in: 1.hour)

    render json: result
  rescue ActiveRecord::StatementInvalid => e
    if e.message.include?('statement timeout')
      Rails.logger.error("[Storage] Analysis timeout for account #{Current.account.id}: #{e.message}")
      render json: {
        error: 'Analysis timed out. Use ?async=true to run in background, or contact support.',
        timeout: true,
        suggestion: 'Add ?async=true to the request URL'
      }, status: :request_timeout
    else
      Rails.logger.error("[Storage] Analysis error for account #{Current.account.id}: #{e.message}\n#{e.backtrace.join("\n")}")
      render json: { error: 'Failed to analyze storage' }, status: :internal_server_error
    end
  rescue StandardError => e
    Rails.logger.error("[Storage] Analysis error for account #{Current.account.id}: #{e.message}\n#{e.backtrace.join("\n")}")
    render json: { error: 'Failed to analyze storage' }, status: :internal_server_error
  end

  # GET /api/v1/accounts/:account_id/storage/status
  # Check status of background analysis
  def status
    cache_key = "storage_analysis:#{Current.account.id}"
    status = Rails.cache.read("#{cache_key}:status")
    
    case status
    when 'in_progress'
      render json: { status: 'in_progress', message: 'Analysis is currently running' }
    when 'completed'
      cached = Rails.cache.read(cache_key)
      render json: { status: 'completed', result: cached }
    when 'timeout'
      error = Rails.cache.read("#{cache_key}:error")
      render json: { status: 'timeout', error: error }, status: :request_timeout
    when 'failed'
      error = Rails.cache.read("#{cache_key}:error")
      render json: { status: 'failed', error: error }, status: :internal_server_error
    else
      render json: { status: 'not_started', message: 'No analysis has been run yet' }
    end
  end

  # GET /api/v1/accounts/:account_id/storage/duplicates
  # Find duplicate files
  def duplicates
    service = AccountStorageService.new(Current.account)
    limit = params[:limit]&.to_i || 50

    duplicates = service.find_duplicates(limit: limit)

    render json: { duplicates: duplicates }
  rescue StandardError => e
    Rails.logger.error("Storage duplicates error: #{e.message}\n#{e.backtrace.join("\n")}")
    render json: { error: 'Failed to find duplicates' }, status: :internal_server_error
  end

  # GET /api/v1/accounts/:account_id/storage/largest_files
  # Find largest files
  def largest_files
    service = AccountStorageService.new(Current.account)
    limit = params[:limit]&.to_i || 20

    files = service.find_largest_files(limit: limit)

    render json: { files: files }
  rescue StandardError => e
    Rails.logger.error("Storage largest_files error: #{e.message}\n#{e.backtrace.join("\n")}")
    render json: { error: 'Failed to find largest files' }, status: :internal_server_error
  end

  # POST /api/v1/accounts/:account_id/storage/cleanup_orphans
  # Clean orphan blobs (blobs without attachments)
  # Note: Processes in batches to handle large datasets
  def cleanup_orphans
    Rails.logger.info("[Storage] Starting orphan cleanup for account #{Current.account.id}")
    start_time = Time.current

    service = AccountStorageService.new(Current.account)
    result = service.cleanup_orphan_blobs

    duration = Time.current - start_time
    Rails.logger.info("[Storage] Cleanup completed in #{duration.round(2)}s for account #{Current.account.id}")

    render json: {
      message: 'Cleanup completed',
      cleaned_count: result[:cleaned_count],
      space_freed: result[:space_freed],
      duration_seconds: duration.round(2)
    }
  rescue StandardError => e
    Rails.logger.error("[Storage] Cleanup error for account #{Current.account.id}: #{e.message}\n#{e.backtrace.join("\n")}")
    render json: { error: 'Failed to cleanup orphan blobs' }, status: :internal_server_error
  end

  # POST /api/v1/accounts/:account_id/storage/deduplicate
  # Deduplicate files with the same checksum
  # Note: This is a heavy operation that can take time on large accounts
  def deduplicate
    Rails.logger.info("[Storage] Starting deduplication for account #{Current.account.id}")
    start_time = Time.current

    service = AccountStorageService.new(Current.account)
    result = service.deduplicate_files

    duration = Time.current - start_time
    Rails.logger.info("[Storage] Deduplication completed in #{duration.round(2)}s for account #{Current.account.id}")

    render json: {
      message: 'Deduplication completed',
      deduplicated_count: result[:deduplicated_count],
      space_saved: result[:space_saved],
      duration_seconds: duration.round(2)
    }
  rescue StandardError => e
    Rails.logger.error("[Storage] Deduplication error for account #{Current.account.id}: #{e.message}\n#{e.backtrace.join("\n")}")
    render json: { error: 'Failed to deduplicate files' }, status: :internal_server_error
  end

  private

  # Determine if analysis should run asynchronously
  # Use async for accounts with >10GB storage or >10k messages
  def should_use_async?
    # Quick check: count messages (faster than blob size calculation)
    message_count = Message.joins(:conversation)
                           .where(conversations: { account_id: Current.account.id })
                           .count
    
    # If >10k messages, assume it's a large account
    return true if message_count > 10_000
    
    # For smaller accounts, check blob count (still faster than size)
    blob_count_sql = AccountStorageService.new(Current.account).send(:account_blob_ids_query).to_sql
    blob_count = ActiveRecord::Base.connection.select_value("SELECT COUNT(*) FROM (#{blob_count_sql}) AS subquery")
    
    blob_count.to_i > 5_000
  rescue StandardError => e
    Rails.logger.warn("[Storage] Error checking account size: #{e.message}, defaulting to async")
    true # Default to async on error
  end

  def check_authorization
    raise Pundit::NotAuthorizedError unless Current.account_user.administrator?
  end
end
