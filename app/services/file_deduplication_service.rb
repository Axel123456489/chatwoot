# frozen_string_literal: true

# Service to handle file deduplication by checksum
# Usage:
#   blob = FileDeduplicationService.attach_or_reuse(file: uploaded_file, record: canned_response, attribute: :files)
#
class FileDeduplicationService
  class << self
    # Attach a file to a record, reusing existing blob if duplicate exists
    # @param file [ActionDispatch::Http::UploadedFile, File, String] - File to attach
    # @param record [ApplicationRecord] - ActiveRecord model with has_one/many_attached
    # @param attribute [Symbol] - Name of the attachment attribute
    # @param deduplicate [Boolean] - Whether to check for duplicates (default: true)
    # @return [ActiveStorage::Blob] - The attached blob (new or existing)
    def attach_or_reuse(file:, record:, attribute:, deduplicate: true)
      return standard_attach(file, record, attribute) unless deduplicate

      # Calculate checksum before creating blob
      checksum = calculate_checksum(file)

      # Check if blob with same checksum exists
      existing_blob = find_existing_blob(checksum)

      if existing_blob
        Rails.logger.info "Reusing existing blob #{existing_blob.id} for #{record.class.name}##{record.id}"
        attach_existing_blob(existing_blob, record, attribute)
        existing_blob
      else
        standard_attach(file, record, attribute)
      end
    end

    # Find duplicate blobs and return statistics
    # @return [Hash] Statistics about duplicates
    def analyze_duplicates
      duplicates = ActiveStorage::Blob.group(:checksum)
                                      .having('COUNT(*) > 1')
                                      .select('checksum, COUNT(*) as count, SUM(byte_size) as total_size')
                                      .order('total_size DESC')

      {
        duplicate_groups: duplicates.count,
        duplicate_files: duplicates.sum(&:count) - duplicates.count,
        wasted_space: duplicates.sum { |d| d.total_size - (d.total_size / d.count) }
      }
    end

    # Deduplicate all attachments for a given record type
    # @param record_class [Class] - ActiveRecord model class
    # @param attribute [Symbol] - Attachment attribute name
    # @return [Hash] Deduplication statistics
    def deduplicate_record_attachments(record_class:, attribute:)
      stats = { deduplicated: 0, space_saved: 0 }

      record_class.find_each do |record|
        attachments = record.public_send(attribute)
        next if attachments.blank?

        attachments.each do |attachment|
          blob = attachment.blob
          next unless blob

          # Find other blobs with same checksum
          duplicate_blobs = ActiveStorage::Blob.where(checksum: blob.checksum)
                                               .where.not(id: blob.id)
                                               .order(:created_at)

          oldest_blob = duplicate_blobs.first
          next unless oldest_blob

          # Use the oldest blob
          attachment.update(blob_id: oldest_blob.id)
          stats[:space_saved] += blob.byte_size
          stats[:deduplicated] += 1

          # Purge current blob if no other attachments reference it
          blob.purge if blob.attachments.reload.empty?
        end
      end

      stats
    end

    private

    # Calculate checksum for a file
    def calculate_checksum(file)
      if file.respond_to?(:tempfile)
        Digest::MD5.file(file.tempfile.path).base64digest
      elsif file.is_a?(String)
        Digest::MD5.file(file).base64digest
      else
        Digest::MD5.file(file.path).base64digest
      end
    end

    # Find existing blob with same checksum
    def find_existing_blob(checksum)
      ActiveStorage::Blob.find_by(checksum: checksum)
    end

    # Attach existing blob to record
    def attach_existing_blob(blob, record, attribute)
      attachment_association = record.public_send(attribute)

      if attachment_association.is_a?(ActiveStorage::Attached::Many)
        # has_many_attached
        record.public_send(attribute).attach(blob)
      else
        # has_one_attached
        record.public_send("#{attribute}=", blob)
        record.save
      end
    end

    # Standard attachment without deduplication
    def standard_attach(file, record, attribute)
      attachment_association = record.public_send(attribute)

      if attachment_association.is_a?(ActiveStorage::Attached::Many)
        record.public_send(attribute).attach(file)
        record.public_send(attribute).attachments.last&.blob
      else
        record.public_send("#{attribute}=", file)
        record.save
        record.public_send(attribute).blob
      end
    end
  end
end
