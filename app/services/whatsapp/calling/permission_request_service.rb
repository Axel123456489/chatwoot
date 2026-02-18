# frozen_string_literal: true

# Service to request call permission from WhatsApp users
# Permission must be granted before business can initiate calls
class Whatsapp::Calling::PermissionRequestService
  include Rails.application.routes.url_helpers

  class PermissionError < StandardError; end
  class AlreadyRequestedError < StandardError; end
  class ContactNotFoundError < StandardError; end

  attr_reader :account, :inbox, :contact, :user

  def initialize(account:, inbox:, contact:, user:)
    @account = account
    @inbox = inbox
    @contact = contact
    @user = user
    raise ArgumentError, 'Inbox must be WhatsApp channel' unless whatsapp_inbox?
    raise ArgumentError, 'Calling not enabled for this inbox' unless calling_enabled?
  end

  def perform
    ActiveRecord::Base.transaction do
      validate_can_request!

      permission = find_or_create_permission

      # Don't request again if already granted or pending
      if permission.granted?
        raise AlreadyRequestedError, 'Permission already granted'
      elsif permission.pending? && permission.requested_at.present? && permission.requested_at > 24.hours.ago
        raise AlreadyRequestedError, 'Permission request already pending'
      end

      # Send permission request message
      send_permission_request_message(permission)

      # Update permission record
      permission.update!(
        status: 'pending',
        requested_at: Time.current,
        requested_by_user_id: user.id
      )

      # Create activity message in conversation
      create_activity_message(permission)

      permission
    end
  rescue StandardError => e
    Rails.logger.error("Permission request failed: #{e.message}")
    Rails.logger.error(e.backtrace.join("\n"))
    raise
  end

  private

  def validate_can_request!
    raise ContactNotFoundError, 'Contact not found' if contact.nil?
    raise PermissionError, 'Contact phone number required' if contact.phone_number.blank?

    # Check if contact has active conversation
    raise PermissionError, 'No active conversation with contact' unless active_conversation?
  end

  def find_or_create_permission
    Whatsapp::CallPermission.find_or_create_by!(
      account: account,
      inbox: inbox,
      contact: contact,
      phone_number_id: inbox.channel.phone_number_id
    ) do |permission|
      permission.status = 'pending'
      permission.remaining_calls = 0
    end
  end

  def send_permission_request_message(permission)
    # Prepare the permission request message
    message_params = {
      phone_number_id: inbox.channel.phone_number_id,
      to: normalize_phone_number(contact.phone_number),
      type: 'text',
      text: {
        body: permission_request_message_text
      },
      # Include context for better tracking
      context: {
        message_id: permission.id.to_s
      }
    }

    # Send via WhatsApp API
    api_adapter = Whatsapp::Calling::ApiAdapter.new(inbox.channel)
    response = api_adapter.send_message(message_params)

    # Store WhatsApp message ID for tracking
    permission.update!(
      whatsapp_message_id: response.dig('messages', 0, 'id')
    )

    response
  end

  def permission_request_message_text
    business_name = inbox.name || account.name

    <<~MESSAGE.strip
      Hola, somos #{business_name}.

      Nos gustaría poder llamarte por WhatsApp para brindarte un mejor servicio.

      Para permitir que podamos llamarte:
      1. Toca en el nombre de nuestro negocio en la parte superior
      2. Desplázate hasta "Permisos de llamada"
      3. Activa "Permitir que #{business_name} me llame"

      Una vez activado, podremos realizar hasta 10 llamadas por día.

      ¿Necesitas ayuda? Responde este mensaje y te asistiremos. 📞
    MESSAGE
  end

  def create_activity_message(_permission)
    conversation = contact.conversations.where(inbox: inbox).last
    return unless conversation

    content = "Solicitud de permiso de llamada enviada a #{contact.name || contact.phone_number}"

    conversation.messages.create!(
      account: account,
      inbox: inbox,
      message_type: :activity,
      content: content,
      sender: user
    )
  end

  def active_conversation?
    contact.conversations.exists?(inbox: inbox)
  end

  def whatsapp_inbox?
    inbox.is_a?(Inbox) && inbox.channel_type == 'Channel::Whatsapp'
  end

  def calling_enabled?
    inbox.channel.calling_config&.dig('enabled') == true
  end

  def normalize_phone_number(phone)
    # Remove any non-digit characters except +
    phone.to_s.gsub(/[^\d+]/, '')
  end

  class << self
    def request_permission(account:, inbox:, contact:, user:)
      new(account: account, inbox: inbox, contact: contact, user: user).perform
    end
  end
end
