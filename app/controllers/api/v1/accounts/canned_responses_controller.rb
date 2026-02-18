class Api::V1::Accounts::CannedResponsesController < Api::V1::Accounts::BaseController
  before_action :fetch_canned_response, only: [:update, :destroy]

  def index
    Rails.logger.info("[CannedResponses#index] account_id=#{Current.account&.id} user_id=#{current_user&.id} params=#{params.slice(:search).to_unsafe_h}")
    @canned_responses = canned_responses
    Rails.logger.info("[CannedResponses#index] found=#{@canned_responses.size}")
  rescue StandardError => e
    Rails.logger.error("[CannedResponses#index] error=#{e.class} message=#{e.message}\n#{e.backtrace&.first(10)&.join("\n")}")
    raise
  end

  def create
    @canned_response = Current.account.canned_responses.new(canned_response_params)

    render json: { error: @canned_response.errors.messages }, status: :unprocessable_entity and return unless @canned_response.valid?

    @canned_response.save!
    process_attachments
  end

  def update
    ActiveRecord::Base.transaction do
      @canned_response.update!(canned_response_params)
      process_attachments
    rescue StandardError => e
      Rails.logger.error e
      render json: { error: @canned_response.errors.messages }.to_json, status: :unprocessable_entity
    end
  end

  def destroy
    @canned_response.destroy!
    head :ok
  end

  private

  def process_attachments
    # Check if blob_ids was explicitly provided (even if empty)
    return unless params.key?(:blob_ids) || params.key?(:blob_id)

    # Collect incoming tokens (supports numeric IDs and signed IDs)
    tokens = if params.key?(:blob_ids)
               Array(params[:blob_ids]).flatten
             elsif params[:blob_id].present?
               [params[:blob_id]]
             else
               []
             end

    tokens = tokens.map(&:to_s).reject(&:blank?)

    Rails.logger.info("[CannedResponses#process_attachments] incoming_tokens=#{tokens}")

    # Resolve tokens to Blob records
    blobs = tokens.filter_map do |t|
      if /\A\d+\z/.match?(t)
        ActiveStorage::Blob.find_by(id: t)
      else
        begin
          ActiveStorage::Blob.find_signed(t)
        rescue StandardError => e
          Rails.logger.warn("[CannedResponses#process_attachments] find_signed failed for token=#{t}: #{e.class} #{e.message}")
          nil
        end
      end
    end

    if blobs.size != tokens.size
      resolved_refs = blobs.flat_map { |b| [b.id.to_s, b.signed_id] }
      missing = tokens - resolved_refs
      Rails.logger.warn("[CannedResponses#process_attachments] some tokens could not be resolved to blobs missing=#{missing}")
    end

    desired_ids = blobs.map { |b| b.id.to_s }
    current_ids = @canned_response.files.map { |att| att.blob_id.to_s }

    Rails.logger.info("[CannedResponses#process_attachments] desired_ids=#{desired_ids} current_ids=#{current_ids}")

    # Purge attachments that are no longer included
    (current_ids - desired_ids).each do |remove_id|
      attachment = @canned_response.files.attachments.find { |att| att.blob_id.to_s == remove_id }
      Rails.logger.info("[CannedResponses#process_attachments] purging blob_id=#{remove_id}")
      attachment&.purge
    end

    # Attach new blobs that are not already attached (with deduplication)
    (desired_ids - current_ids).each do |add_id|
      blob = blobs.find { |b| b.id.to_s == add_id }
      next unless blob

      # Check for existing blob with same checksum (deduplication)
      existing_blob = ActiveStorage::Blob.where(checksum: blob.checksum)
                                         .where.not(id: blob.id)
                                         .order(:created_at)
                                         .first

      if existing_blob
        Rails.logger.info("[CannedResponses#process_attachments] found duplicate blob_id=#{existing_blob.id} for new blob_id=#{add_id} checksum=#{blob.checksum}")

        # Attach the existing blob instead
        @canned_response.files.attach(existing_blob)

        # Purge the duplicate blob if it's not attached to anything else
        if blob.attachments.reload.empty?
          Rails.logger.info("[CannedResponses#process_attachments] purging duplicate blob_id=#{add_id}")
          blob.purge
        end
      else
        Rails.logger.info("[CannedResponses#process_attachments] attaching blob_id=#{add_id} key=#{blob.key} content_type=#{blob.content_type} filename=#{blob.filename}")
        @canned_response.files.attach(blob)

        # Verify that the underlying file exists in the configured storage
        begin
          exists = blob.service.exist?(blob.key)
          Rails.logger.info("[CannedResponses#process_attachments] blob storage exist?=#{exists} key=#{blob.key}")
        rescue StandardError => e
          Rails.logger.warn("[CannedResponses#process_attachments] error checking storage existence for blob_id=#{add_id}: #{e.class} #{e.message}")
        end
      end
    end
  end

  def fetch_canned_response
    @canned_response = Current.account.canned_responses.find(params[:id])
  end

  def canned_response_params
    params.require(:canned_response).permit(:short_code, :content, :content_type, :custom_role_id)
  end

  def canned_responses
    base_query = Current.account
                        .canned_responses
                        .with_attached_files
                        .includes(:custom_role)

    # Apply role filter only if the column exists (prevents 500 before migrations run)
    if ActiveRecord::Base.connection.column_exists?(:canned_responses, :custom_role_id) && Current.account_user
      Rails.logger.info("[CannedResponses#index] applying role filter custom_role_id=#{Current.account_user&.custom_role_id}")
      role_id = Current.account_user.custom_role_id
      base_query = base_query.where('custom_role_id IS NULL OR custom_role_id = ?', role_id)
    end

    scoped_query = if params[:search]
                     Rails.logger.info("[CannedResponses#index] applying search='#{params[:search]}'")
                     base_query.where('short_code ILIKE :search OR content ILIKE :search',
                                      search: "%#{params[:search]}%").order_by_search(params[:search])
                   else
                     base_query
                   end

    fetch_canned_responses(scoped_query)
  end

  def fetch_canned_responses(relation)
    if Rails.configuration.action_controller.perform_caching
      cache_key = [
        'accounts',
        Current.account&.id || 'unknown',
        'canned_responses',
        Current.account_user&.custom_role_id || 'all',
        params[:search].presence || 'all',
        relation.cache_key_with_version
      ]
      Rails.cache.fetch(cache_key, expires_in: 5.minutes) { relation.load.to_a }
    else
      relation.load.to_a
    end
  end
end
