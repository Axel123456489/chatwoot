# frozen_string_literal: true

# Service to initiate outbound WhatsApp calls
class Whatsapp::Calling::OutboundCallService
  include Rails.application.routes.url_helpers
  include Events::Types

  class PermissionError < StandardError; end
  class LimitError < StandardError; end
  class CallInitiationError < StandardError; end

  attr_reader :account, :inbox, :contact, :user, :conversation

  def initialize(account:, inbox:, contact:, user:, conversation: nil)
    @account = account
    @inbox = inbox
    @contact = contact
    @user = user
    @conversation = conversation
  end

  def perform
    ActiveRecord::Base.transaction do
      validate_can_call!

      # Find or create conversation
      @conversation ||= find_or_create_conversation

      # Create a local placeholder and initiate call via API to get the real call id
      call_id = initiate_call_with_provider

      # Store call information in conversation
      store_call_data(call_id)

      # Create WhatsappCall record
      whatsapp_call = create_whatsapp_call_record(call_id)

      # Create call message using CallMessageBuilder
      create_call_message_with_builder(whatsapp_call)

      # Decrement remaining calls
      decrement_permission_calls

      # Broadcast to real-time
      broadcast_call_initiated(call_id)

      {
        conversation: conversation,
        call_id: call_id,
        status: 'initiated'
      }
    end
  rescue StandardError => e
    Rails.logger.error("Outbound call failed: #{e.message}")
    Rails.logger.error(e.backtrace.join("\n"))
    raise
  end

  private

  def validate_can_call!
    # Check if inbox supports calling
    raise CallInitiationError, 'Calling not enabled for this inbox' unless inbox.channel_type == 'Channel::Whatsapp' && inbox.channel.calling_enabled?

    # Check permission
    permission = find_permission
    raise PermissionError, 'No call permission for this contact' unless permission
    raise PermissionError, 'Call permission expired' if permission.expired?
    raise PermissionError, 'Call permission not granted' unless permission.permission_status == 'granted'

    # Check daily limit
    raise LimitError, 'Daily call limit reached for this contact' if permission.remaining_calls <= 0

    # Check if there's already an active call
    raise CallInitiationError, 'There is already an active call' if active_call_exists?
  end

  def find_permission
    @find_permission ||= Whatsapp::CallPermission.find_by(
      account: account,
      inbox: inbox,
      contact: contact,
      phone_number_id: inbox.channel.phone_number_id
    )
  end

  def find_or_create_conversation
    scoped_conversations = contact.conversations.where(inbox: inbox)

    if inbox.lock_to_single_conversation?
      existing_conversation = scoped_conversations.order(updated_at: :desc).first
      return existing_conversation if existing_conversation
    else
      # Try to find recent conversation
      recent_conversation = scoped_conversations
                            .where('created_at > ?', 24.hours.ago)
                            .last
      return recent_conversation if recent_conversation
    end

    # Create new conversation
    ContactInboxBuilder.new(
      contact: contact,
      inbox: inbox,
      source_id: contact.phone_number
    ).perform

    conversation_params = {
      account: account,
      inbox: inbox,
      contact: contact,
      contact_inbox: contact.contact_inboxes.find_by(inbox: inbox),
      additional_attributes: {
        initiated_at: {
          timestamp: Time.current.to_i
        }
      }
    }

    ::Conversation.create!(conversation_params)
  end

  def generate_local_call_id
    "local-#{SecureRandom.hex(8)}"
  end

  def store_call_data(call_id)
    call_data = conversation.additional_attributes['whatsapp_call'] || {}

    call_data.merge!({
                       'id' => call_id,
                       'direction' => 'outbound',
                       'status' => 'initiated',
                       'initiated_at' => Time.current.iso8601,
                       'initiated_by' => user.id,
                       'status_reason' => 'awaiting_browser_offer'
                     })

    conversation.update!(
      additional_attributes: conversation.additional_attributes.merge(
        'whatsapp_call' => call_data,
        # Store call_id at top level for terminate webhook lookup
        # Initially it's a temporary local ID, will be replaced with WhatsApp call_id later
        'call_id' => call_id
      )
    )
  end

  def create_whatsapp_call_record(call_id)
    WhatsappCall.create!(
      account: account,
      inbox: inbox,
      contact: contact,
      conversation: conversation,
      call_id: call_id,
      direction: 'outbound',
      status: 'initiated',
      initiated_at: Time.current
    )
  end

  def create_call_message_with_builder(whatsapp_call)
    builder = Whatsapp::Calling::CallMessageBuilder.new(
      conversation: conversation,
      whatsapp_call: whatsapp_call
    )

    builder.create_initiated_message
  end

  def decrement_permission_calls
    permission = find_permission
    permission.decrement!(:remaining_calls)
  end

  def active_call_exists?
    call_data = conversation&.additional_attributes&.dig('whatsapp_call')
    return false unless call_data

    active_statuses = %w[initiated ringing accepted connecting connected on_hold]
    active_statuses.include?(call_data['status'])
  end

  def broadcast_call_initiated(call_id)
    Rails.configuration.dispatcher.dispatch(
      WHATSAPP_OUTBOUND_CALL_INITIATED,
      Time.zone.now,
      call_id: call_id,
      conversation: conversation,
      user: user
    )
  end

  def initiate_call_with_provider
    local_call_id = generate_local_call_id

    response = Whatsapp::Calling::ApiAdapter.new(inbox.channel).initiate_call(
      to: normalize_phone_number(contact.phone_number),
      sdp_offer: conversation&.additional_attributes&.dig('sdp_offer'),
      tracking_data: { account_id: account.id, inbox_id: inbox.id, conversation_id: conversation&.id, local_call_id: local_call_id }.compact
    )

    provider_call_id = response.dig('calls', 0, 'id')
    provider_call_id.presence || local_call_id
  rescue StandardError => e
    Rails.logger.error("[WhatsApp Calling] Failed to initiate outbound call: #{e.message}")
    raise CallInitiationError, 'Failed to initiate WhatsApp call'
  end

  def normalize_phone_number(phone)
    phone.to_s.gsub(/[^\d+]/, '')
  end

  class << self
    def initiate_call(account:, inbox:, contact:, user:, conversation: nil)
      new(
        account: account,
        inbox: inbox,
        contact: contact,
        user: user,
        conversation: conversation
      ).perform
    end
  end
end
