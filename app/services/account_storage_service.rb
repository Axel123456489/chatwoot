# frozen_string_literal: true

# Service to analyze and manage storage for a specific account
# rubocop:disable Metrics/ClassLength
class AccountStorageService
  attr_reader :account

  # Timeout for long-running queries (10 minutes)
  QUERY_TIMEOUT = 600_000 # milliseconds
  # Batch size for processing large datasets
  BATCH_SIZE = 1000

  def initialize(account)
    @account = account
  end

  # Execute query with timeout to prevent hanging on large datasets
  def with_timeout(&block)
    ActiveRecord::Base.connection.execute("SET LOCAL statement_timeout = #{QUERY_TIMEOUT}")
    result = block.call
    ActiveRecord::Base.connection.execute('SET LOCAL statement_timeout = DEFAULT')
    result
  rescue ActiveRecord::StatementInvalid => e
    ActiveRecord::Base.connection.execute('SET LOCAL statement_timeout = DEFAULT')
    raise e if e.message.include?('statement timeout')

    raise
  end

  # Analyze storage usage for the account
  # @return [Hash] Storage statistics
  def analyze
    with_timeout do
      {
        overview: storage_overview,
        by_content_type: storage_by_content_type,
        orphan_blobs: orphan_blob_stats,
        duplicates: duplicate_stats,
        by_source: storage_by_source
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
  def deduplicate_files
    with_timeout do
      stats = { deduplicated_count: 0, space_saved: 0 }
      checksums = duplicate_checksums
      total = checksums.size

      Rails.logger.info("[Storage] Found #{total} duplicate checksum groups to deduplicate")

      checksums.each_with_index do |checksum, index|
        result = deduplicate_by_checksum(checksum)
        stats[:deduplicated_count] += result[:count]
        stats[:space_saved] += result[:space_saved]

        # Log progress every 10 checksums or at completion
        if (index + 1) % 10 == 0 || (index + 1) == total
          Rails.logger.info("[Storage] Deduplicated #{index + 1}/#{total} checksum groups, " \
                           "saved #{(stats[:space_saved].to_f / 1.megabyte).round(2)} MB so far")
        end
      end

      Rails.logger.info("[Storage] Deduplication complete: #{stats[:deduplicated_count]} files, " \
                       "#{(stats[:space_saved].to_f / 1.megabyte).round(2)} MB saved")
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
  def orphan_blob_stats
    orphan_blobs = find_orphan_blobs

    {
      count: orphan_blobs.count,
      size: orphan_blobs.sum(:byte_size)
    }
  end

  # Get duplicate statistics
  def duplicate_stats
    blob_subquery = account_blob_ids_query.to_sql

    sql = 'SELECT checksum, COUNT(*) as count, SUM(byte_size) as total_size ' \
          'FROM active_storage_blobs ' \
          "WHERE id IN (#{blob_subquery}) " \
          'GROUP BY checksum ' \
          'HAVING COUNT(*) > 1'

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
  def duplicate_checksums
    ActiveStorage::Blob
      .where(id: account_blob_ids_query)
      .group(:checksum)
      .having('COUNT(*) > 1')
      .pluck(:checksum)
  end

  # Count blobs by checksum for this account
  def count_by_checksum(checksum)
    ActiveStorage::Blob.where(checksum: checksum, id: account_blob_ids_query).count
  end

  # Deduplicate blobs with the same checksum
  # rubocop:disable Metrics/BlockLength
  def deduplicate_by_checksum(checksum)
    blobs = ActiveStorage::Blob.where(checksum: checksum, id: account_blob_ids_query).order(:created_at)

    return { count: 0, space_saved: 0 } if blobs.count <= 1

    master_blob = blobs.first
    duplicate_blobs = blobs.offset(1)

    count = 0
    space_saved = 0

    Rails.logger.debug("[Storage] Deduplicating checksum #{checksum}: #{duplicate_blobs.count} duplicates of master blob ##{master_blob.id}")

    # Keep message attachment IDs as subquery (no pluck)
    attachment_ids = Attachment.where(
      message_id: Message.joins(:conversation)
                         .where(conversations: { account_id: account.id })
                         .select(:id)
    ).select(:id)

    duplicate_blobs.each do |duplicate_blob|
      # For each duplicate blob, we need to either:
      # 1. Update the attachment to point to master_blob (if no conflict)
      # 2. Delete the attachment (if master_blob attachment already exists for that record)

      # 1. Message attachments (Attachment model with has_one_attached :file)
      ActiveStorage::Attachment
        .where(record_type: 'Attachment', record_id: attachment_ids, name: 'file', blob_id: duplicate_blob.id)
        .find_each do |attachment|
        # Check if this record already has an attachment with master_blob
        existing = ActiveStorage::Attachment.find_by(
          record_type: attachment.record_type,
          record_id: attachment.record_id,
          name: attachment.name,
          blob_id: master_blob.id
        )

        if existing
          # Already has master_blob, just delete the duplicate attachment
          attachment.destroy
        else
          # Update to point to master_blob
          attachment.update(blob_id: master_blob.id)
        end
      end

      # 2. Canned response attachments
      canned_response_ids = account.canned_responses.select(:id)
      ActiveStorage::Attachment
        .where(record_type: 'CannedResponse', record_id: canned_response_ids, blob_id: duplicate_blob.id)
        .find_each do |attachment|
        existing = ActiveStorage::Attachment.find_by(
          record_type: attachment.record_type,
          record_id: attachment.record_id,
          name: attachment.name,
          blob_id: master_blob.id
        )

        if existing
          attachment.destroy
        else
          attachment.update(blob_id: master_blob.id)
        end
      end

      # 3. User avatars
      user_ids = account.users.select(:id)
      ActiveStorage::Attachment
        .where(record_type: 'User', record_id: user_ids, name: 'avatar', blob_id: duplicate_blob.id)
        .find_each do |attachment|
        existing = ActiveStorage::Attachment.find_by(
          record_type: attachment.record_type,
          record_id: attachment.record_id,
          name: attachment.name,
          blob_id: master_blob.id
        )

        if existing
          attachment.destroy
        else
          attachment.update(blob_id: master_blob.id)
        end
      end

      # 4. Contact avatars
      contact_ids = account.contacts.select(:id)
      ActiveStorage::Attachment
        .where(record_type: 'Contact', record_id: contact_ids, name: 'avatar', blob_id: duplicate_blob.id)
        .find_each do |attachment|
        existing = ActiveStorage::Attachment.find_by(
          record_type: attachment.record_type,
          record_id: attachment.record_id,
          name: attachment.name,
          blob_id: master_blob.id
        )

        if existing
          attachment.destroy
        else
          attachment.update(blob_id: master_blob.id)
        end
      end

      space_saved += duplicate_blob.byte_size
      count += 1

      # Purge if no attachments remain
      duplicate_blob.purge if duplicate_blob.attachments.reload.empty?
    end

    Rails.logger.debug("[Storage] Checksum #{checksum} deduplication complete: #{count} files, #{(space_saved.to_f / 1.megabyte).round(2)} MB")
    { count: count, space_saved: space_saved }
  end
  # rubocop:enable Metrics/BlockLength
end
# rubocop:enable Metrics/ClassLength
