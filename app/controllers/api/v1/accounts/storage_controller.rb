# frozen_string_literal: true

class Api::V1::Accounts::StorageController < Api::V1::Accounts::BaseController
  before_action :check_authorization

  # GET /api/v1/accounts/:account_id/storage/analyze
  # Analyze storage usage for the account
  def analyze
    service = AccountStorageService.new(Current.account)
    analysis = service.analyze

    render json: {
      overview: analysis[:overview],
      by_content_type: analysis[:by_content_type],
      orphan_blobs: analysis[:orphan_blobs],
      duplicates: analysis[:duplicates],
      by_source: analysis[:by_source]
    }
  rescue StandardError => e
    Rails.logger.error("Storage analyze error: #{e.message}\n#{e.backtrace.join("\n")}")
    render json: { error: 'Failed to analyze storage' }, status: :internal_server_error
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
  def cleanup_orphans
    service = AccountStorageService.new(Current.account)
    result = service.cleanup_orphan_blobs

    render json: {
      message: 'Cleanup completed',
      cleaned_count: result[:cleaned_count],
      space_freed: result[:space_freed]
    }
  rescue StandardError => e
    Rails.logger.error("Storage cleanup_orphans error: #{e.message}\n#{e.backtrace.join("\n")}")
    render json: { error: 'Failed to cleanup orphan blobs' }, status: :internal_server_error
  end

  # POST /api/v1/accounts/:account_id/storage/deduplicate
  # Deduplicate files with the same checksum
  def deduplicate
    service = AccountStorageService.new(Current.account)
    result = service.deduplicate_files

    render json: {
      message: 'Deduplication completed',
      deduplicated_count: result[:deduplicated_count],
      space_saved: result[:space_saved]
    }
  rescue StandardError => e
    Rails.logger.error("Storage deduplicate error: #{e.message}\n#{e.backtrace.join("\n")}")
    render json: { error: 'Failed to deduplicate files' }, status: :internal_server_error
  end

  private

  def check_authorization
    raise Pundit::NotAuthorizedError unless Current.account_user.administrator?
  end
end
