# frozen_string_literal: true

# Service to update call permission status from WhatsApp webhooks
class Whatsapp::Calling::PermissionStatusService
  attr_reader :account, :inbox, :webhook_data

  def initialize(account:, inbox:, webhook_data:)
    @account = account
    @inbox = inbox
    @webhook_data = webhook_data
  end

  def perform
    permission_data = extract_permission_data
    return unless permission_data

    permission = find_permission(permission_data)
    return unless permission

    update_permission(permission, permission_data)

    # Notify user if granted
    notify_permission_granted(permission) if permission.granted?

    permission
  end

  private

  def extract_permission_data
    # Extract from webhook data
    # Format: { "contact" => "+1234567890", "status" => "granted", "expires_at" => "2024-01-01T00:00:00Z" }
    value = webhook_data.dig('entry', 0, 'changes', 0, 'value')
    return unless value

    {
      phone_number: value['phone_number'],
      status: value['permission_status'],
      expires_at: value['permission_expires_at']
    }
  end

  def find_permission(permission_data)
    phone = normalize_phone_number(permission_data[:phone_number])

    contact = Contact.where(account: account)
                     .where('phone_number LIKE ?', "%#{phone[-10..]}")
                     .first

    return unless contact

    Whatsapp::CallPermission.find_by(
      account: account,
      inbox: inbox,
      contact: contact,
      phone_number_id: inbox.channel.phone_number_id
    )
  end

  def update_permission(permission, permission_data)
    status = map_status(permission_data[:status])

    permission.update!(
      status: status,
      granted_at: status == 'granted' ? Time.current : nil,
      expires_at: parse_expiration(permission_data[:expires_at]),
      remaining_calls: status == 'granted' ? 10 : 0
    )
  end

  def map_status(whatsapp_status)
    case whatsapp_status&.downcase
    when 'granted', 'approved'
      'granted'
    when 'denied', 'rejected'
      'denied'
    when 'revoked'
      'revoked'
    else
      'pending'
    end
  end

  def parse_expiration(expires_at_str)
    return nil if expires_at_str.blank?

    Time.zone.parse(expires_at_str)
  rescue ArgumentError
    nil
  end

  def notify_permission_granted(permission)
    conversation = permission.contact.conversations
                             .where(inbox: inbox)
                             .last
    return unless conversation

    content = "✅ #{permission.contact.name || permission.contact.phone_number} ha otorgado permiso para recibir llamadas. Puedes realizar hasta 10 llamadas por día."

    conversation.messages.create!(
      account: account,
      inbox: inbox,
      message_type: :activity,
      content: content
    )

    # Broadcast to agents
    Rails.configuration.dispatcher.dispatch(
      WHATSAPP_CALL_PERMISSION_GRANTED,
      Time.zone.now,
      permission: permission,
      conversation: conversation
    )
  end

  def normalize_phone_number(phone)
    phone.to_s.gsub(/[^\d+]/, '')
  end

  class << self
    def update_from_webhook(account:, inbox:, webhook_data:)
      new(account: account, inbox: inbox, webhook_data: webhook_data).perform
    end
  end
end
