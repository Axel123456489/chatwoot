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
  # Redis keys for user-requested cancellation
  DEDUP_CANCEL_KEY   = 'storage_deduplication_cancel:%<account_id>s'
  CLEANUP_CANCEL_KEY = 'storage_cleanup_cancel:%<account_id>s'

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
  def with_timeout
    timeout_ms = query_timeout
    timeout_seconds = timeout_ms / 1000
    Rails.logger.info("[AccountStorageService] Using #{timeout_ms / 60_000}min timeout for account #{account.id}")

    # Use SET (without LOCAL) since we're not in a transaction block
    # This is safe because it only affects the current connection session
    ActiveRecord::Base.connection.execute("SET statement_timeout = '#{timeout_seconds}s'")
    result = yield
    ActiveRecord::Base.connection.execute('RESET statement_timeout')
    result
  rescue StandardError
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
    bytes_freed = 0
    cancelled = false
    orphan_blobs.find_each(batch_size: BATCH_SIZE) do |blob|
      if cleanup_cancellation_requested?
        cancelled = true
        Rails.logger.info("[StorageCleanup] Cleanup cancelled by user for account #{account.id} after #{cleaned} blobs")
        break
      end
      bytes_freed += blob.byte_size
      blob.purge
      cleaned += 1
      Rails.logger.info("[StorageCleanup] Progress: #{cleaned}/#{count}") if (cleaned % 100).zero?
    end

    Rails.logger.info("[StorageCleanup] Completed: #{cleaned} blobs purged")

    {
      cleaned_count: cleaned,
      space_freed: bytes_freed,
      cancelled: cancelled
    }
  end

  # Deduplicate files for this account
  # @return [Hash] Deduplication statistics
  # @param batch_size [Integer] Checksums per batch (default: 500)
  # @param max_checksums [Integer] Max checksums to process, nil = all
  #
  # Performance:
  #   - Materialises account blob IDs into a temp table ONCE so the 5-source
  #     UNION subquery is never repeated inside the loop.
  #   - Keyset cursor pagination (O(log n) per page).
  #   - Bulk SQL for attachment reassignment and deletion, zero S3 calls inline.
  def deduplicate_files(batch_size: 500, max_checksums: nil)
    # rubocop:disable Metrics/BlockLength
    with_timeout do
      # --- Materialise blob IDs once into a temp table -------------------------
      # The UNION subquery across 5 sources (messages, canned, avatars, portals)
      # can take 10-30 min when evaluated inside the WHERE clause of every batch
      # query on large accounts. A temp table is filled once and reused for free.
      conn = ActiveRecord::Base.connection
      conn.execute(<<~SQL.squish)
        CREATE TEMP TABLE IF NOT EXISTS _dedup_account_blobs AS
        #{account_blob_ids_query.to_sql}
      SQL
      conn.execute('CREATE INDEX IF NOT EXISTS _dedup_account_blobs_id ON _dedup_account_blobs (id)')
      @dedup_blob_subquery = 'SELECT id FROM _dedup_account_blobs'

      Rails.logger.info("[Storage] Temp table _dedup_account_blobs created for account #{account.id}")

      stats = { deduplicated_count: 0, space_saved: 0, processed_checksums: 0 }
      last_checksum = nil
      batch_num = 0

      loop do
        break if max_checksums && stats[:processed_checksums] >= max_checksums

        if dedup_cancellation_requested?
          stats[:cancelled] = true
          Rails.logger.info("[Storage] Deduplication cancelled by user for account #{account.id}")
          break
        end

        checksums = duplicate_checksums_keyset(after: last_checksum, limit: batch_size)
        break if checksums.empty?

        batch_num += 1
        Rails.logger.info("[Storage] Batch #{batch_num} – #{checksums.size} checksum groups " \
                          "(cursor: #{last_checksum&.slice(0, 10) || 'start'})")

        result = deduplicate_checksum_batch(checksums)
        stats[:deduplicated_count] += result[:count]
        stats[:space_saved]        += result[:space_saved]
        stats[:processed_checksums] += checksums.size
        last_checksum = checksums.last

        Rails.logger.info("[Storage] Batch #{batch_num} done: #{result[:count]} blobs removed, " \
                          "#{(result[:space_saved].to_f / 1.megabyte).round(2)} MB saved " \
                          "| running total #{stats[:deduplicated_count]} / #{(stats[:space_saved].to_f / 1.megabyte).round(2)} MB")

        sleep(0.01)
      end

      Rails.logger.info("[Storage] Deduplication complete: #{stats[:deduplicated_count]} files, " \
                        "#{(stats[:space_saved].to_f / 1.megabyte).round(2)} MB saved, " \
                        "#{stats[:processed_checksums]} checksum groups processed")
      stats
    ensure
      # Temp tables are session-scoped but clean up explicitly to be safe
      begin
        conn.execute('DROP TABLE IF EXISTS _dedup_account_blobs')
      rescue StandardError
        nil
      end
    end
    # rubocop:enable Metrics/BlockLength
  end
  # rubocop:enable Metrics/MethodLength

  # Find duplicate files by checksum
  # @return [Array<Hash>] Array of duplicate file groups
  # rubocop:disable Metrics/MethodLength
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
  # rubocop:enable Metrics/MethodLength

  # Find largest files
  # @return [Array<Hash>] Array of largest files with duplicate info
  # rubocop:disable Metrics/MethodLength
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
  # rubocop:enable Metrics/MethodLength

  private

  def dedup_cancellation_requested?
    Rails.cache.read(format(DEDUP_CANCEL_KEY, account_id: account.id)).present?
  end

  def cleanup_cancellation_requested?
    Rails.cache.read(format(CLEANUP_CANCEL_KEY, account_id: account.id)).present?
  end

  # rubocop:disable Metrics/MethodLength
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

  # Get duplicate checksums using keyset cursor – O(log n) per page.
  # @param after [String, nil] Return checksums strictly greater than this value
  # @param limit [Integer] Page size
  def duplicate_checksums_keyset(after: nil, limit: 500)
    blob_subquery = @dedup_blob_subquery || account_blob_ids_query.to_sql
    after_clause  = after ? "AND checksum > #{ActiveRecord::Base.connection.quote(after)}" : ''

    sql = <<~SQL.squish
      SELECT checksum
      FROM active_storage_blobs
      WHERE id IN (#{blob_subquery})
      #{after_clause}
      GROUP BY checksum
      HAVING COUNT(*) > 1
      ORDER BY checksum ASC
      LIMIT #{limit.to_i}
    SQL

    ActiveRecord::Base.connection.select_values(sql)
  end

  # Process an entire batch of checksums in bulk.
  # Issues at most:
  #   1 query  – fetch all blobs for all checksums
  #   1 query  – fetch all master-blob attachment keys (conflict detection)
  #   1 query  – fetch all duplicate-blob attachments
  #   1 query  – bulk DELETE conflicting attachments
  #   1 query  – bulk UPDATE remaining attachments (single CASE WHEN expression)
  #   1 query  – find still-attached blobs
  #   1 Redis  – push orphaned storage keys to purge queue (no S3 calls here)
  #   1 query  – bulk DELETE orphaned blob DB records
  def deduplicate_checksum_batch(checksums)
    blob_subquery  = @dedup_blob_subquery || account_blob_ids_query.to_sql
    quoted_cs      = checksums.map { |c| ActiveRecord::Base.connection.quote(c) }.join(', ')

    # --- 1. Fetch all relevant blobs in one query --------------------------------
    # NOTE: intentionally NOT filtering by blob_subquery (account scope) here.
    # Checksums were discovered within this account's scope, but the actual merge
    # must be global: blobs from other accounts with the same checksum should also
    # be collapsed into the single oldest master so that a global
    # `SELECT checksum, COUNT(*) … HAVING COUNT(*) > 1` reaches 0 after dedup.
    # still_attached and bulk_purge_blobs are already global, so this is safe.
    rows = ActiveRecord::Base.connection.select_all(<<~SQL.squish)
      SELECT id, checksum, byte_size
      FROM active_storage_blobs
      WHERE checksum IN (#{quoted_cs})
      ORDER BY checksum ASC, created_at ASC
    SQL

    master_map = {}  # dup_blob_id  -> master_blob_id
    dup_sizes  = {}  # dup_blob_id  -> byte_size

    rows.group_by { |r| r['checksum'] }.each_value do |blobs|
      next if blobs.size <= 1

      master_id = blobs.first['id'].to_i
      blobs.drop(1).each do |b|
        dup_id             = b['id'].to_i
        master_map[dup_id] = master_id
        dup_sizes[dup_id]  = b['byte_size'].to_i
      end
    end

    return { count: 0, space_saved: 0 } if master_map.empty?

    all_dup_ids    = master_map.keys
    all_master_ids = master_map.values.uniq

    # --- 2. Master conflicts (one query) ----------------------------------------
    master_conflicts = Hash.new { |h, k| h[k] = Set.new }
    ActiveStorage::Attachment
      .where(blob_id: all_master_ids)
      .pluck(:blob_id, :record_type, :record_id, :name)
      .each { |bid, rt, ri, n| master_conflicts[bid.to_i] << [rt, ri.to_i, n] }

    # --- 3. Duplicate attachments (one query) ------------------------------------
    ids_to_delete  = []
    att_to_master  = {}  # attachment_id -> target master_blob_id

    ActiveStorage::Attachment
      .where(blob_id: all_dup_ids)
      .pluck(:id, :blob_id, :record_type, :record_id, :name)
      .each do |att_id, blob_id, rt, ri, n|
        master_id = master_map[blob_id.to_i]
        key       = [rt, ri.to_i, n]

        if master_conflicts[master_id].include?(key)
          ids_to_delete << att_id
        else
          att_to_master[att_id] = master_id
          master_conflicts[master_id] << key  # prevent intra-batch conflicts
        end
      end

    # --- 4. Bulk delete conflicting attachments (one query) ----------------------
    ActiveStorage::Attachment.where(id: ids_to_delete).delete_all if ids_to_delete.any?

    # --- 5. Bulk update via VALUES join – avoids CASE WHEN with thousands of
    #        entries that causes row-lock contention on busy tables.
    #        lock_timeout = 5s applied inside an explicit transaction so SET LOCAL
    #        actually takes effect on the UPDATE statement.  Only LockWaitTimeout
    #        is rescued (skip the batch); other errors bubble up so the job fails
    #        loudly instead of silently leaving blobs unreferenced by master.
    if att_to_master.any?
      conn = ActiveRecord::Base.connection
      values_sql = att_to_master.map { |att_id, mid| "(#{att_id}, #{mid})" }.join(', ')
      begin
        conn.transaction do
          conn.execute("SET LOCAL lock_timeout = '5s'")
          conn.execute(<<~SQL.squish)
            UPDATE active_storage_attachments AS a
            SET blob_id = v.new_blob_id
            FROM (VALUES #{values_sql}) AS v(att_id, new_blob_id)
            WHERE a.id = v.att_id
          SQL
        end
      rescue ActiveRecord::LockWaitTimeout => e
        Rails.logger.warn("[Storage] lock_timeout on attachment UPDATE, skipping batch: #{e.message[0..120]}")
      end
    end

    # --- 6. Find which dup blobs are now truly orphaned (one query) --------------
    still_attached = ActiveStorage::Attachment
                     .where(blob_id: all_dup_ids)
                     .distinct.pluck(:blob_id)
                     .to_set(&:to_i)

    blobs_to_purge = all_dup_ids.reject { |id| still_attached.include?(id) }
    space_saved    = blobs_to_purge.sum { |id| dup_sizes[id] }

    # --- 7. Bulk purge: parallel storage deletes + one SQL DELETE ----------------
    bulk_purge_blobs(blobs_to_purge)

    { count: blobs_to_purge.size, space_saved: space_saved }
  end
  # rubocop:enable Metrics/MethodLength, Metrics/AbcSize

  # Two-phase purge:
  #   Phase 1 (this method): save storage keys to Redis, delete blob DB records.
  #                          Called inline during deduplication – no S3 calls,
  #                          so dedup becomes pure DB work.
  #   Phase 2 (StorageFilePurgeJob): reads keys from Redis and deletes from S3
  #                                  asynchronously with high parallelism.
  #
  # Redis list key: storage_purge_queue:{account_id}
  PURGE_QUEUE_REDIS_KEY = 'storage_purge_queue:%<account_id>s'
  PURGE_QUEUE_TTL       = 7.days.to_i
  PURGE_THREADS         = 32

  def bulk_purge_blobs(blob_ids)
    return if blob_ids.empty?

    # 1. Fetch keys BEFORE deleting records (they're gone after delete_all)
    keys = ActiveStorage::Blob.where(id: blob_ids).pluck(:key)

    # 2. Push keys to Redis purge queue so the async purge job can process them
    queue_key = format(PURGE_QUEUE_REDIS_KEY, account_id: account.id)
    Sidekiq.redis do |r|
      r.rpush(queue_key, keys) if keys.any?
      r.expire(queue_key, PURGE_QUEUE_TTL)
    end

    # 3. Delete blob DB records only – zero S3 calls, very fast
    ActiveStorage::Blob.where(id: blob_ids).delete_all
  end

  # Actual S3/GCS storage deletion – called by StorageFilePurgeJob, not inline.
  # Deletes storage objects in parallel to saturate network throughput.
  public def purge_storage_keys(keys)
    return if keys.empty?

    slice_size = [(keys.size.to_f / PURGE_THREADS).ceil, 1].max
    keys.each_slice(slice_size).map do |slice|
      Thread.new do
        slice.each do |key|
          ActiveStorage::Blob.service.delete(key)
        rescue StandardError => e
          Rails.logger.warn("[Storage] Could not delete key #{key}: #{e.message}")
        end
      end
    end.each(&:join)
  end

  # Return the number of keys currently pending S3 deletion for this account
  public def pending_purge_count
    queue_key = format(PURGE_QUEUE_REDIS_KEY, account_id: account.id)
    Sidekiq.redis { |r| r.llen(queue_key) }.to_i
  end

  # Get duplicate checksums for this account
  # @param limit [Integer] Maximum checksums to return (default: 1000)
  # @param offset [Integer] Offset for pagination (default: 0)
  # @return [Array<String>] Array of checksums with duplicates
  def duplicate_checksums(limit: 1000, offset: 0)
    # Use raw SQL with LIMIT/OFFSET for better performance on large datasets
    blob_subquery = account_blob_ids_query.to_sql

    sql = <<-SQL.squish
      SELECT checksum#{' '}
      FROM active_storage_blobs#{' '}
      WHERE id IN (#{blob_subquery})
      GROUP BY checksum#{' '}
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
  def deduplicate_by_checksum(checksum)
    blobs = ActiveStorage::Blob.where(checksum: checksum, id: account_blob_ids_query).order(:created_at)

    return { count: 0, space_saved: 0 } if blobs.count <= 1

    master_blob = blobs.first
    duplicate_blob_ids = blobs.offset(1).pluck(:id)

    return { count: 0, space_saved: 0 } if duplicate_blob_ids.empty?

    count = 0
    space_saved = 0

    Rails.logger.debug do
      "[Storage] Deduplicating checksum #{checksum[0..8]}...: #{duplicate_blob_ids.size} duplicates of master blob ##{master_blob.id}"
    end

    # Process each duplicate blob
    duplicate_blob_ids.each do |duplicate_blob_id|
      space_saved += deduplicate_single_blob(duplicate_blob_id, master_blob.id)
      count += 1
    end

    Rails.logger.debug { "[Storage] Checksum #{checksum[0..8]}... complete: #{count} files, #{(space_saved.to_f / 1.megabyte).round(2)} MB" }
    { count: count, space_saved: space_saved }
  end

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
                                  .to_set { |a| [a.record_type, a.record_id, a.name] }

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
    ActiveStorage::Attachment.where(id: attachment_ids_to_update).update_all(blob_id: master_blob_id) if attachment_ids_to_update.any? # rubocop:disable Rails/SkipsModelValidations

    # Batch delete conflicting attachments
    ActiveStorage::Attachment.where(id: attachment_ids_to_delete).delete_all if attachment_ids_to_delete.any?

    # Purge the duplicate blob if it has no attachments left
    remaining_count = ActiveStorage::Attachment.where(blob_id: duplicate_blob_id).count
    duplicate_blob.purge if remaining_count.zero?

    space_saved
  end
  # rubocop:enable Metrics/MethodLength, Metrics/AbcSize
end
# rubocop:enable Metrics/ClassLength
