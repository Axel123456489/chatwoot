# frozen_string_literal: true

# rubocop:disable Metrics/ClassLength
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

    # Cache for 2 hours (same as async analysis)
    Rails.cache.write(cache_key, result, expires_in: 2.hours)
    Rails.cache.write("#{cache_key}:status", 'completed', expires_in: 2.hours)

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
    cached_result = Rails.cache.read(cache_key)

    # Si hay datos cacheados pero no hay status (status expiró), considerar como completado
    status = 'completed' if cached_result.present? && status.blank?

    case status
    when 'in_progress'
      render json: { status: 'in_progress', message: 'Analysis is currently running' }
    when 'completed'
      # Devolver los datos junto con el status
      if cached_result.present?
        render json: { status: 'completed', result: cached_result }
      else
        # Los datos expiraron, marcar como not_started
        render json: { status: 'not_started', message: 'Cached results expired. Run a new analysis.' }
      end
    when 'timeout'
      error = Rails.cache.read("#{cache_key}:error")
      render json: { status: 'timeout', error: error }, status: :request_timeout
    when 'failed'
      error = Rails.cache.read("#{cache_key}:error")
      render json: { status: 'failed', error: error }, status: :internal_server_error
    else
      # No hay status, verificar si hay datos cacheados de todas formas
      if cached_result.present?
        render json: { status: 'completed', result: cached_result }
      else
        render json: { status: 'not_started', message: 'No analysis has been run yet' }
      end
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
  # Note: Runs in background via Sidekiq
  def cleanup_orphans
    Rails.logger.info("[Storage] Enqueuing orphan cleanup for account #{Current.account.id}")

    StorageCleanupJob.perform_later(Current.account.id)

    render json: {
      message: 'Cleanup job enqueued',
      status: 'in_progress'
    }
  rescue StandardError => e
    Rails.logger.error("[Storage] Cleanup enqueue error for account #{Current.account.id}: #{e.message}")
    render json: { error: 'Failed to enqueue cleanup job' }, status: :internal_server_error
  end

  # GET /api/v1/accounts/:account_id/storage/cleanup_status
  # Get status of cleanup job
  def cleanup_status
    status_data = Rails.cache.read("storage_cleanup_status:#{Current.account.id}")

    if status_data
      render json: status_data
    else
      render json: {
        status: 'not_started',
        message: 'No cleanup has been run yet'
      }
    end
  rescue StandardError => e
    Rails.logger.error("[Storage] Cleanup status error: #{e.message}")
    render json: { error: 'Failed to get cleanup status' }, status: :internal_server_error
  end

  # POST /api/v1/accounts/:account_id/storage/deduplicate
  # Deduplicate files with the same checksum
  # Note: Runs in background via Sidekiq
  def deduplicate
    Rails.logger.info("[Storage] Enqueuing deduplication for account #{Current.account.id}")

    StorageDeduplicationJob.perform_later(Current.account.id)

    render json: {
      message: 'Deduplication job enqueued',
      status: 'in_progress'
    }
  rescue StandardError => e
    Rails.logger.error("[Storage] Deduplication enqueue error for account #{Current.account.id}: #{e.message}")
    render json: { error: 'Failed to enqueue deduplication job' }, status: :internal_server_error
  end

  # GET /api/v1/accounts/:account_id/storage/deduplication_status
  # Get status of deduplication job
  def deduplication_status
    status_data = Rails.cache.read("storage_deduplication_status:#{Current.account.id}")

    if status_data
      render json: status_data
    else
      render json: {
        status: 'not_started',
        message: 'No deduplication has been run yet'
      }
    end
  rescue StandardError => e
    Rails.logger.error("[Storage] Deduplication status error: #{e.message}")
    render json: { error: 'Failed to get deduplication status' }, status: :internal_server_error
  end

  # DELETE /api/v1/accounts/:account_id/storage/cancel_deduplication
  def cancel_deduplication
    account_id = Current.account.id
    status_data = Rails.cache.read("storage_deduplication_status:#{account_id}")
    current_status = status_data&.dig(:status) || status_data&.dig('status') || 'not_started'

    return render json: { error: 'No deduplication in progress' }, status: :unprocessable_entity unless current_status == 'in_progress'

    Rails.cache.write("storage_deduplication_cancel:#{account_id}", true, expires_in: 10.minutes)
    Rails.logger.info("[Storage] Deduplication cancel requested for account #{account_id}")

    render json: { status: 'cancelling', message: 'Cancellation requested. The process will stop at the next checkpoint.' }
  rescue StandardError => e
    Rails.logger.error("[Storage] Cancel deduplication error: #{e.message}")
    render json: { error: 'Failed to cancel deduplication' }, status: :internal_server_error
  end

  # DELETE /api/v1/accounts/:account_id/storage/cancel_cleanup
  def cancel_cleanup
    account_id = Current.account.id
    status_data = Rails.cache.read("storage_cleanup_status:#{account_id}")
    current_status = status_data&.dig(:status) || status_data&.dig('status') || 'not_started'

    return render json: { error: 'No cleanup in progress' }, status: :unprocessable_entity unless current_status == 'in_progress'

    Rails.cache.write("storage_cleanup_cancel:#{account_id}", true, expires_in: 10.minutes)
    Rails.logger.info("[Storage] Cleanup cancel requested for account #{account_id}")

    render json: { status: 'cancelling', message: 'Cancellation requested. The process will stop at the next checkpoint.' }
  rescue StandardError => e
    Rails.logger.error("[Storage] Cancel cleanup error: #{e.message}")
    render json: { error: 'Failed to cancel cleanup' }, status: :internal_server_error
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
# rubocop:enable Metrics/ClassLength
