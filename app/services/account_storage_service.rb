# frozen_string_literal: true

# Service to analyze and manage storage for a specific account
# rubocop:disable Metrics/ClassLength
class AccountStorageService
  attr_reader :account

  # Timeout for long-running queries
  # 10 minutes for small accounts, 60 minutes for large accounts
  DEFAULT_QUERY_TIMEOUT = 600_000 # milliseconds (10 min)
  LARGE_ACCOUNT_TIMEOUT = 3_600_000 # milliseconds (60 min)
  # Batch size for processing large datasets
  BATCH_SIZE = 1000
  # Threshold for considering an account "large" (10k messages)
  LARGE_ACCOUNT_MESSAGE_THRESHOLD = 10_000

  def initialize(account)
    @account = account
    @is_large_account = nil
  end

  # Determine if account is large (cached)
  def large_account?
    return @is_large_account unless @is_large_account.nil?

    @is_large_account = Message.joins(:conversation)
                               .where(conversations: { account_id: account.id })
                               .limit(LARGE_ACCOUNT_MESSAGE_THRESHOLD + 1)
                               .count > LARGE_ACCOUNT_MESSAGE_THRESHOLD
  end

  # Get appropriate timeout based on account size
  def query_timeout
    large_account? ? LARGE_ACCOUNT_TIMEOUT : DEFAULT_QUERY_TIMEOUT
  end

  # Execute query with timeout to prevent hanging on large datasets
  def with_timeout(&block)
    timeout_ms = query_timeout
    timeout_seconds = timeout_ms / 1000
    Rails.logger.info("[AccountStorageService] Using #{timeout_ms / 60_000}min timeout for account #{account.id}")
    
    # Use SET (without LOCAL) since we're not in a transaction block
    # This is safe because it only affects the current connection session
    ActiveRecord::Base.connection.execute("SET statement_timeout = '#{timeout_seconds}s'")
    result = block.call
    ActiveRecord::Base.connection.execute('RESET statement_timeout')
    result
  rescue StandardError => e
    # Always reset timeout on error
    ActiveRecord::Base.connection.execute('RESET statement_timeout')
    raise
  end

  # Analyze storage usage for the account
  # @return [Hash] Storage statistics
  # @param progress_callback [Proc] Optional callback to report progress
  def analyze(progress_callback: nil)
    with_timeout do
      progress_callback&.call('overview', 0.2)
      Rails.logger.info("[AccountStorageService] Analyzing overview for account #{account.id}")
      overview_result = storage_overview
      
      progress_callback&.call('content_types', 0.4)
      Rails.logger.info("[AccountStorageService] Analyzing by content type for account #{account.id}")
      by_content_type_result = storage_by_content_type
      
      progress_callback&.call('orphans', 0.6)
      Rails.logger.info("[AccountStorageService] Analyzing orphan blobs for account #{account.id}")
      orphan_result = orphan_blob_stats
      
      progress_callback&.call('duplicates', 0.8)
      Rails.logger.info("[AccountStorageService] Analyzing duplicates for account #{account.id}")
      duplicates_result = duplicate_stats
      
      progress_callback&.call('sources', 0.9)
      Rails.logger.info("[AccountStorageService] Analyzing by source for account #{account.id}")
      by_source_result = storage_by_source
      
      progress_callback&.call('complete', 1.0)
      
      {
        overview: overview_result,
        by_content_type: by_content_type_result,
        orphan_blobs: orphan_result,
        duplicates: duplicates_result,
        by_source: by_source_result
      }
    end
  end

  # Clean orphan blobs (blobs without attachments) for this account
  # @return [Hash] Cleanup statistics
  # Optimized for large datasets - processes in batches
  def cleanup_orphan_blobs
    orphan_blobs = find_orphan_blobs
    count = orphan_blobs.count
    size = orphan_blobs.sum(:byte_size)

    Rails.logger.info("[StorageCleanup] Starting cleanup of #{count} orphan blobs (#{size} bytes) for account #{account.id}")

    cleaned = 0
    orphan_blobs.find_each(batch_size: BATCH_SIZE) do |blob|
      blob.purge
      cleaned += 1
      Rails.logger.info("[StorageCleanup] Progress: #{cleaned}/#{count}") if (cleaned % 100).zero?
    end

    Rails.logger.info("[StorageCleanup] Completed: #{cleaned} blobs purged")

    {
      cleaned_count: count,
      space_freed: size
    }
  end

  # Deduplicate files for this account
  # @return [Hash] Deduplication statistics
  # @param batch_size [Integer] Number of checksums to process per batch (default: 100)
  # @param max_checksums [Integer] Maximum checksums to process (nil = all)
  def deduplicate_files(batch_size: 100, max_checksums: nil)
    with_timeout do
      stats = { deduplicated_count: 0, space_saved: 0, processed_checksums: 0 }
      
      # Get checksums in batches using LIMIT/OFFSET for better performance
      offset = 0
      batch_num = 0
      
      loop do
        checksums = duplicate_checksums(limit: batch_size, offset: offset)
        break if checksums.empty?
        break if max_checksums && offset >= max_checksums

        batch_num += 1
        Rails.logger.info("[Storage] Processing batch #{batch_num} (#{checksums.size} checksum groups, offset: #{offset})")

        checksums.each do |checksum|
          result = deduplicate_by_checksum(checksum)
          stats[:deduplicated_count] += result[:count]
          stats[:space_saved] += result[:space_saved]
          stats[:processed_checksums] += 1
        end

        Rails.logger.info("[Storage] Batch #{batch_num} complete: #{stats[:deduplicated_count]} total files deduplicated, " \
                         "#{(stats[:space_saved].to_f / 1.megabyte).round(2)} MB saved so far")

        offset += batch_size
        
        # Small sleep to avoid overwhelming the database
        sleep(0.1)
      end

      Rails.logger.info("[Storage] Deduplication complete: #{stats[:deduplicated_count]} files, " \
                       "#{(stats[:space_saved].to_f / 1.megabyte).round(2)} MB saved, " \
                       "#{stats[:processed_checksums]} checksum groups processed")
      stats
    end
  end

  # Find duplicate files by checksum
  # @return [Array<Hash>] Array of duplicate file groups
  def find_duplicates(limit: 50)
    blob_subquery = account_blob_ids_query.to_sql

    sql = 'SELECT checksum, COUNT(*) as count, MAX(filename) as filename, ' \
          'MAX(content_type) as content_type, SUM(byte_size) as total_size ' \
          'FROM active_storage_blobs ' \
          "WHERE id IN (#{blob_subquery}) " \
          'GROUP BY checksum ' \
          'HAVING COUNT(*) > 1 ' \
          'ORDER BY total_size DESC ' \
          "LIMIT #{limit.to_i}"

    ActiveRecord::Base.connection.select_all(sql).map do |row|
      count = row['count'].to_i
      total_size = row['total_size'].to_i
      wasted_space = total_size - (total_size / count)
      {
        checksum: row['checksum'],
        filename: row['filename'],
        content_type: row['content_type'],
        count: count,
        total_size: total_size,
        wasted_space: wasted_space
      }
    end
  end

  # Find largest files
  # @return [Array<Hash>] Array of largest files with duplicate info
  def find_largest_files(limit: 20)
    blob_subquery = account_blob_ids_query.to_sql

    # Get duplicate checksums for the account
    duplicate_checksums_set = Set.new(duplicate_checksums)

    # Get largest files
    sql = 'SELECT id, filename, content_type, byte_size, checksum, created_at ' \
          'FROM active_storage_blobs ' \
          "WHERE id IN (#{blob_subquery}) " \
          'ORDER BY byte_size DESC ' \
          "LIMIT #{limit.to_i}"

    ActiveRecord::Base.connection.select_all(sql).map do |row|
      checksum = row['checksum']
      is_duplicate = duplicate_checksums_set.include?(checksum)

      {
        id: row['id'],
        filename: row['filename'],
        content_type: row['content_type'],
        size: row['byte_size'].to_i,
        is_duplicate: is_duplicate,
        duplicate_count: is_duplicate ? count_by_checksum(checksum) : 1,
        created_at: row['created_at']
      }
    end
  end

  private

  # Get storage overview statistics
  # Optimized for large datasets - uses single query with CTEs
  def storage_overview
    sql = <<-SQL.squish
      WITH account_blobs AS (
        #{account_blob_ids_query.to_sql}
      )
      SELECT
        COUNT(DISTINCT ab.id) as total_blobs,
        COALESCE(SUM(asb.byte_size), 0) as total_size
      FROM account_blobs ab
      INNER JOIN active_storage_blobs asb ON asb.id = ab.id
    SQL

    result = ActiveRecord::Base.connection.select_one(sql)

    # Count attachments separately (faster than joining everything)
    message_attachments_count = Attachment.where(
      message_id: Message.joins(:conversation)
                         .where(conversations: { account_id: account.id })
                         .select(:id)
    ).count

    canned_attachments_count = ActiveStorage::Attachment
                               .where(record_type: 'CannedResponse')
                               .joins('INNER JOIN canned_responses ON canned_responses.id = active_storage_attachments.record_id')
                               .where(canned_responses: { account_id: account.id })
                               .count

    user_avatar_count = ActiveStorage::Attachment
                        .where(record_type: 'User', name: 'avatar')
                        .joins('INNER JOIN account_users ON account_users.user_id = active_storage_attachments.record_id')
                        .where(account_users: { account_id: account.id })
                        .count

    contact_avatar_count = ActiveStorage::Attachment
                           .where(record_type: 'Contact', name: 'avatar')
                           .joins('INNER JOIN contacts ON contacts.id = active_storage_attachments.record_id')
                           .where(contacts: { account_id: account.id })
                           .count

    {
      total_blobs: result['total_blobs'].to_i,
      total_size: result['total_size'].to_i,
      total_attachments: message_attachments_count + canned_attachments_count + user_avatar_count + contact_avatar_count
    }
  end

  # Get storage statistics by content type
  def storage_by_content_type
    blob_subquery = account_blob_ids_query.to_sql

    sql = 'SELECT content_type, COUNT(*) as count, SUM(byte_size) as size ' \
          'FROM active_storage_blobs ' \
          "WHERE id IN (#{blob_subquery}) " \
          'GROUP BY content_type ' \
          'ORDER BY size DESC ' \
          'LIMIT 20'

    ActiveRecord::Base.connection.select_all(sql).map do |row|
      {
        content_type: row['content_type'] || 'unknown',
        count: row['count'].to_i,
        size: row['size'].to_i
      }
    end
  end

  # Get orphan blob statistics
  # Optimized version for large accounts - uses SQL directly
  def orphan_blob_stats
    blob_subquery = account_blob_ids_query.to_sql
    
    # Use a more efficient query for large datasets
    sql = <<-SQL.squish
      SELECT COUNT(*) as count, COALESCE(SUM(byte_size), 0) as size
      FROM active_storage_blobs asb
      WHERE asb.id IN (#{blob_subquery})
      AND NOT EXISTS (
        SELECT 1 FROM active_storage_attachments asa
        WHERE asa.blob_id = asb.id
      )
    SQL
    
    result = ActiveRecord::Base.connection.select_one(sql)

    {
      count: result['count'].to_i,
      size: result['size'].to_i
    }
  end

  # Get duplicate statistics
  # Optimized version with LIMIT to prevent timeout on large accounts
  def duplicate_stats
    blob_subquery = account_blob_ids_query.to_sql

    # For large accounts, limit the analysis to reduce query time
    limit_clause = large_account? ? 'LIMIT 100000' : ''
    
    sql = <<-SQL.squish
      SELECT checksum, COUNT(*) as count, SUM(byte_size) as total_size
      FROM active_storage_blobs
      WHERE id IN (#{blob_subquery})
      GROUP BY checksum
      HAVING COUNT(*) > 1
      #{limit_clause}
    SQL

    results = ActiveRecord::Base.connection.select_all(sql)
    groups = results.count
    duplicate_count = results.sum { |r| r['count'].to_i } - groups
    duplicate_size = results.sum do |r|
      count = r['count'].to_i
      total_size = r['total_size'].to_i
      total_size - (total_size / count)
    end

    {
      groups: groups,
      files: duplicate_count,
      wasted_space: duplicate_size
    }
  end

  # Get storage by source (messages, canned_responses, etc.)
  def storage_by_source
    sources = {}

    # Messages attachments — all SQL, no Ruby arrays
    msg_blobs = ActiveStorage::Attachment
                .where(record_type: 'Attachment', name: 'file')
                .where(
                  record_id: Attachment.where(
                    message_id: Message.joins(:conversation)
                                       .where(conversations: { account_id: account.id })
                                       .select(:id)
                  ).select(:id)
                )
                .select(:blob_id)

    sources[:messages] = {
      count: msg_blobs.count,
      size: ActiveStorage::Blob.where(id: msg_blobs).sum(:byte_size)
    }

    # Canned responses
    canned_blobs = ActiveStorage::Attachment
                   .where(record_type: 'CannedResponse')
                   .joins('INNER JOIN canned_responses ON canned_responses.id = active_storage_attachments.record_id ' \
                          "AND active_storage_attachments.record_type = 'CannedResponse'")
                   .where(canned_responses: { account_id: account.id })
                   .select(:blob_id)

    sources[:canned_responses] = {
      count: canned_blobs.count,
      size: ActiveStorage::Blob.where(id: canned_blobs).sum(:byte_size)
    }

    # Avatars (users + contacts) — single UNION subquery
    user_avatar_blobs = ActiveStorage::Attachment
                        .where(record_type: 'User', name: 'avatar')
                        .joins('INNER JOIN account_users ON account_users.user_id = active_storage_attachments.record_id')
                        .where(account_users: { account_id: account.id })
                        .select(:blob_id)

    contact_avatar_blobs = ActiveStorage::Attachment
                           .where(record_type: 'Contact', name: 'avatar')
                           .joins('INNER JOIN contacts ON contacts.id = active_storage_attachments.record_id')
                           .where(contacts: { account_id: account.id })
                           .select(:blob_id)

    avatar_union_sql = [user_avatar_blobs, contact_avatar_blobs].map(&:to_sql).join(' UNION ')
    avatar_blob_ids = ActiveStorage::Blob.where("id IN (#{avatar_union_sql})").select(:id)

    sources[:avatars] = {
      count: avatar_blob_ids.count,
      size: ActiveStorage::Blob.where(id: avatar_blob_ids).sum(:byte_size)
    }

    sources
  end

  # Find orphan blobs for this account
  def find_orphan_blobs
    ActiveStorage::Blob
      .where(id: account_blob_ids_query)
      .left_joins(:attachments)
      .where(active_storage_attachments: { id: nil })
  end

  # Returns an AR relation (subquery) of blob IDs belonging to this account.
  # Never materialises IDs in Ruby – always kept as SQL subquery so callers
  # can compose it directly inside WHERE id IN (subquery).
  def account_blob_ids_query
    # Message attachments: conversations → messages → attachments → active_storage_attachments
    message_blobs = ActiveStorage::Attachment
                    .where(record_type: 'Attachment', name: 'file')
                    .where(
                      record_id: Attachment.where(
                        message_id: Message.joins(:conversation)
                                           .where(conversations: { account_id: account.id })
                                           .select(:id)
                      ).select(:id)
                    )
                    .select(:blob_id)

    # Canned response attachments
    canned_blobs = ActiveStorage::Attachment
                   .where(record_type: 'CannedResponse')
                   .joins('INNER JOIN canned_responses ON canned_responses.id = active_storage_attachments.record_id ' \
                          "AND active_storage_attachments.record_type = 'CannedResponse'")
                   .where(canned_responses: { account_id: account.id })
                   .select(:blob_id)

    # User avatars
    user_blobs = ActiveStorage::Attachment
                 .where(record_type: 'User', name: 'avatar')
                 .joins('INNER JOIN account_users ON account_users.user_id = active_storage_attachments.record_id')
                 .where(account_users: { account_id: account.id })
                 .select(:blob_id)

    # Contact avatars
    contact_blobs = ActiveStorage::Attachment
                    .where(record_type: 'Contact', name: 'avatar')
                    .joins('INNER JOIN contacts ON contacts.id = active_storage_attachments.record_id')
                    .where(contacts: { account_id: account.id })
                    .select(:blob_id)

    # Portal logos
    portal_blobs = ActiveStorage::Attachment
                   .where(record_type: 'Portal', name: 'logo')
                   .joins('INNER JOIN portals ON portals.id = active_storage_attachments.record_id')
                   .where(portals: { account_id: account.id })
                   .select(:blob_id)

    # UNION all sources in SQL so the DB handles the merge, not Ruby.
    # AR 7.1 does not expose .union on relation instances; build it via Arel.
    union_sql = [message_blobs, canned_blobs, user_blobs, contact_blobs, portal_blobs]
                .map(&:to_sql)
                .join(' UNION ')

    ActiveStorage::Blob.where("id IN (#{union_sql})").select(:id)
  end

  # Get duplicate checksums for this account
  # @param limit [Integer] Maximum checksums to return (default: 1000)
  # @param offset [Integer] Offset for pagination (default: 0)
  # @return [Array<String>] Array of checksums with duplicates
  def duplicate_checksums(limit: 1000, offset: 0)
    # Use raw SQL with LIMIT/OFFSET for better performance on large datasets
    blob_subquery = account_blob_ids_query.to_sql
    
    sql = <<-SQL
      SELECT checksum 
      FROM active_storage_blobs 
      WHERE id IN (#{blob_subquery})
      GROUP BY checksum 
      HAVING COUNT(*) > 1
      ORDER BY checksum
      LIMIT #{limit.to_i}
      OFFSET #{offset.to_i}
    SQL
    
    ActiveRecord::Base.connection.select_values(sql)
  end

  # Count blobs by checksum for this account
  def count_by_checksum(checksum)
    ActiveStorage::Blob.where(checksum: checksum, id: account_blob_ids_query).count
  end

  # Deduplicate blobs with the same checksum (optimized version)
  # rubocop:disable Metrics/MethodLength, Metrics/AbcSize
  def deduplicate_by_checksum(checksum)
    blobs = ActiveStorage::Blob.where(checksum: checksum, id: account_blob_ids_query).order(:created_at)

    return { count: 0, space_saved: 0 } if blobs.count <= 1

    master_blob = blobs.first
    duplicate_blob_ids = blobs.offset(1).pluck(:id)

    return { count: 0, space_saved: 0 } if duplicate_blob_ids.empty?

    count = 0
    space_saved = 0

    Rails.logger.debug("[Storage] Deduplicating checksum #{checksum[0..8]}...: #{duplicate_blob_ids.size} duplicates of master blob ##{master_blob.id}")

    # Process each duplicate blob
    duplicate_blob_ids.each do |duplicate_blob_id|
      space_saved += deduplicate_single_blob(duplicate_blob_id, master_blob.id)
      count += 1
    end

    Rails.logger.debug("[Storage] Checksum #{checksum[0..8]}... complete: #{count} files, #{(space_saved.to_f / 1.megabyte).round(2)} MB")
    { count: count, space_saved: space_saved }
  end
  # rubocop:enable Metrics/MethodLength, Metrics/AbcSize

  # Deduplicate a single blob by reassigning its attachments to master
  # rubocop:disable Metrics/MethodLength, Metrics/AbcSize
  def deduplicate_single_blob(duplicate_blob_id, master_blob_id)
    duplicate_blob = ActiveStorage::Blob.find(duplicate_blob_id)
    space_saved = duplicate_blob.byte_size

    # Get all attachments for this duplicate blob
    attachments = ActiveStorage::Attachment.where(blob_id: duplicate_blob_id)

    # Group attachments by (record_type, record_id, name) to detect conflicts
    attachments_by_record = attachments.group_by { |a| [a.record_type, a.record_id, a.name] }

    # Get existing master blob attachments to detect conflicts
    existing_master_attachments = ActiveStorage::Attachment
                                   .where(blob_id: master_blob_id)
                                   .select(:record_type, :record_id, :name)
                                   .map { |a| [a.record_type, a.record_id, a.name] }
                                   .to_set

    # Split attachments into: can_update (no conflict) and must_delete (conflict exists)
    attachment_ids_to_update = []
    attachment_ids_to_delete = []

    attachments_by_record.each do |key, atts|
      if existing_master_attachments.include?(key)
        # Conflict: record already has master_blob, delete these attachments
        attachment_ids_to_delete.concat(atts.map(&:id))
      else
        # No conflict: can update to point to master_blob
        attachment_ids_to_update.concat(atts.map(&:id))
      end
    end

    # Batch update attachments to point to master blob
    if attachment_ids_to_update.any?
      ActiveStorage::Attachment.where(id: attachment_ids_to_update).update_all(blob_id: master_blob_id)
    end

    # Batch delete conflicting attachments
    if attachment_ids_to_delete.any?
      ActiveStorage::Attachment.where(id: attachment_ids_to_delete).delete_all
    end

    # Purge the duplicate blob if it has no attachments left
    remaining_count = ActiveStorage::Attachment.where(blob_id: duplicate_blob_id).count
    duplicate_blob.purge if remaining_count.zero?

    space_saved
  end
  # rubocop:enable Metrics/MethodLength, Metrics/AbcSize
end
# rubocop:enable Metrics/ClassLength
