module FileTypeHelper
  # NOTE: video, audio, image, etc are filetypes previewable in frontend
  def file_type(content_type)
    return :image if image_file?(content_type)
    return :video if video_file?(content_type)
    return :audio if content_type&.include?('audio/')

    :file
  end

  # Used in case of DIRECT_UPLOADS_ENABLED=true or when referencing existing blobs (e.g., from canned responses)
  # Supports both signed_id (string) and numeric blob_id
  def file_type_by_signed_id(identifier)
    blob = if /\A\d+\z/.match?(identifier.to_s)
             # Numeric blob_id
             ActiveStorage::Blob.find_by(id: identifier)
           else
             # Signed ID
             ActiveStorage::Blob.find_signed(identifier)
           end
    file_type(blob&.content_type)
  rescue StandardError => e
    Rails.logger.warn("[FileTypeHelper] Failed to determine file type for identifier=#{identifier}: #{e.class} #{e.message}")
    :file
  end

  def image_file?(content_type)
    [
      'image/jpeg',
      'image/png',
      'image/gif',
      'image/bmp',
      'image/webp',
      'image'
    ].include?(content_type)
  end

  def video_file?(content_type)
    [
      'video/ogg',
      'video/mp4',
      'video/webm',
      'video/quicktime',
      'video'
    ].include?(content_type)
  end
end
