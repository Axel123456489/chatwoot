# frozen_string_literal: true

# Builds standardized payloads for workflow integrations
module WorkflowIntegrations
  class PayloadBuilder
    attr_reader :conversation, :message, :event

    def initialize(conversation:, message: nil, event: nil)
      @conversation = conversation
      @message = message
      @event = event
    end

    def build
      payload = {
        event: event_name,
        conversation: conversation_data,
        contact: contact_data
      }

      payload[:message] = message_data if message.present?
      payload[:event_info] = event&.data&.dig(:event_info) if event&.data&.dig(:event_info)

      payload
    end

    private

    def event_name
      return 'message.created' if message.present?

      event.try(:name) || event.try(:event) || event.try(:type) || 'conversation.updated'
    end

    def conversation_data
      {
        id: conversation.display_id,
        conversation_id: conversation.id,
        display_id: conversation.display_id,
        account_id: conversation.account_id,
        status: conversation.status,
        channel: conversation.inbox.channel_type,
        inbox_id: conversation.inbox_id,
        inbox_name: conversation.inbox.name,
        created_at: conversation.created_at.iso8601,
        updated_at: conversation.updated_at.iso8601,
        custom_attributes: conversation.custom_attributes || {},
        additional_attributes: conversation.additional_attributes || {}
      }
    end

    def contact_data
      contact = conversation.contact
      {
        id: contact.id,
        name: contact.name,
        email: contact.email,
        phone_number: contact.phone_number,
        identifier: contact.identifier,
        custom_attributes: contact.custom_attributes || {},
        additional_attributes: contact.additional_attributes || {}
      }
    end

    def message_data
      data = {
        id: message.id,
        content: message.content,
        content_type: message.content_type,
        message_type: message.message_type,
        created_at: message.created_at.iso8601,
        private: message.private
      }

      data[:attachments] = attachment_data if message.attachments.present?
      data
    end

    def attachment_data
      message.attachments.map do |attachment|
        {
          id: attachment.id,
          file_type: attachment.file_type,
          data_url: attachment.download_url,
          file_url: attachment.file_url
        }
      end
    end
  end
end
