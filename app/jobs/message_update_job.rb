class MessageUpdateJob < ApplicationJob
  queue_as :default

  def perform(message_id)
    Rails.logger.info "[MessageUpdateJob] ===== JOB STARTED ===== message_id=#{message_id}"

    message = Message.find_by(id: message_id)
    unless message
      Rails.logger.error "[MessageUpdateJob] Message not found: id=#{message_id}"
      return
    end

    Rails.logger.info "[MessageUpdateJob] Message found: id=#{message.id}, content='#{message.content}'"
    Rails.logger.info "[MessageUpdateJob] Attachments count: #{message.attachments.count}"

    if message.attachments.any?
      message.attachments.each_with_index do |attachment, index|
        Rails.logger.info "[MessageUpdateJob] Attachment ##{index + 1}: id=#{attachment.id}, file_type=#{attachment.file_type}"
        Rails.logger.info "[MessageUpdateJob]   - file_attached: #{attachment.file.attached?}"
        Rails.logger.info "[MessageUpdateJob]   - file_url: #{attachment.file_url.presence || 'MISSING'}"

        if attachment.file.attached?
          Rails.logger.info "[MessageUpdateJob]   - blob id: #{attachment.file.blob.id}"
          Rails.logger.info "[MessageUpdateJob]   - content_type: #{attachment.file.content_type}"
          Rails.logger.info "[MessageUpdateJob]   - byte_size: #{attachment.file.byte_size}"
        end

        # Get the push_event_data to see what will be sent
        event_data = attachment.push_event_data
        Rails.logger.info "[MessageUpdateJob]   - push_event_data: #{event_data.inspect}"
      end
    else
      Rails.logger.warn '[MessageUpdateJob] No attachments found!'
    end

    # Get the full message push_event_data
    message_event_data = message.push_event_data
    Rails.logger.info "[MessageUpdateJob] Full message push_event_data keys: #{message_event_data.keys.inspect}"
    if message_event_data[:attachments]
      Rails.logger.info "[MessageUpdateJob] Attachments in push_event_data: #{message_event_data[:attachments].inspect}"
    end

    # Trigger the update event which will broadcast to the frontend
    Rails.logger.info '[MessageUpdateJob] Calling send_update_event...'
    message.send_update_event

    Rails.logger.info "[MessageUpdateJob] ===== JOB COMPLETED ===== message_id=#{message_id}"
  end
end
