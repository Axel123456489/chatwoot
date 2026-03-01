class Whatsapp::Calling::InboundCallBuilder
  attr_reader :account, :inbox, :channel, :call_data, :metadata

  def initialize(account:, inbox:, call_data:, metadata:)
    @account = account
    @inbox = inbox
    @channel = @inbox.channel
    @call_data = call_data
    @metadata = metadata
    @call_id = call_data['id']
    # Normalize phone numbers to E.164 format (add + if missing)
    @from_number = normalize_phone_number(call_data['from'])
    @to_number = normalize_phone_number(call_data['to'])
    @sdp_offer = call_data.dig('session', 'sdp')
  end

  def perform
    validate_calling_enabled!

    ActiveRecord::Base.transaction do
      contact = ensure_contact!
      contact_inbox = ensure_contact_inbox!(contact)
      conversation = find_or_create_conversation!(contact, contact_inbox)

      # Don't pre-accept - let agent manually accept the call
      # The call will ring and agent must click "Accept" in the widget
      # Note: WhatsApp may disconnect if not answered within ~30 seconds

      # Create call message in the conversation
      create_call_message!(conversation)

      # Notify agents about incoming call
      notify_agents(conversation)

      conversation
    end
  end

  private

  def validate_calling_enabled!
    return if @channel&.calling_enabled?

    raise StandardError, 'Calling is not enabled for this WhatsApp channel'
  end

  def ensure_contact!
    contact = account.contacts.find_by(phone_number: @from_number)
    return contact if contact

    account.contacts.create!(
      phone_number: @from_number,
      name: @from_number,
      identifier: @from_number
    )
  end

  def ensure_contact_inbox!(contact)
    contact_inbox = ContactInbox.find_or_create_by!(
      contact: contact,
      inbox: inbox
    ) do |record|
      record.source_id = @from_number
    end

    contact_inbox.update!(source_id: @from_number) if @from_number.present? && contact_inbox.source_id != @from_number

    contact_inbox
  end

  def find_or_create_conversation!(contact, contact_inbox)
    # First, try to find existing conversation by call_id (in case of retry/duplicate webhook)
    conversation = account.conversations.find_by(
      identifier: @call_id
    )

    return conversation if conversation

    # If lock_to_single_conversation is enabled, reuse the last conversation (even if closed)
    if inbox.lock_to_single_conversation?
      existing_conversation = account.conversations
                                     .where(contact: contact, inbox: inbox)
                                     .order(updated_at: :desc)
                                     .first

      if existing_conversation
        Rails.logger.info "[WHATSAPP_CALLS] Lock to single conversation enabled, reusing conversation #{existing_conversation.id} (status: #{existing_conversation.status})"

        # Reopen conversation if it's resolved
        existing_conversation.open! if existing_conversation.resolved?

        # Add call information to existing conversation
        existing_conversation.update!(
          additional_attributes: (existing_conversation.additional_attributes || {}).merge(
            'call_id' => @call_id,
            'call_direction' => 'inbound',
            'call_status' => 'ringing',
            'has_active_call' => true,
            'sdp_offer' => @sdp_offer
          ).compact
        )

        # Create WhatsappCall record linked to this conversation
        create_whatsapp_call_record!(existing_conversation)

        return existing_conversation
      end
    else
      # Check if there's an existing open conversation with this contact in this inbox
      # This allows the call to be part of an ongoing conversation
      existing_conversation = account.conversations
                                     .where(contact: contact, inbox: inbox)
                                     .where(status: [:open, :pending])
                                     .order(updated_at: :desc)
                                     .first

      if existing_conversation
        Rails.logger.info "[WHATSAPP_CALLS] Found existing open conversation #{existing_conversation.id}, adding call to it"

        # Add call information to existing conversation
        existing_conversation.update!(
          additional_attributes: (existing_conversation.additional_attributes || {}).merge(
            'call_id' => @call_id,
            'call_direction' => 'inbound',
            'call_status' => 'ringing',
            'has_active_call' => true,
            'sdp_offer' => @sdp_offer
          ).compact
        )

        # Create WhatsappCall record linked to this conversation
        create_whatsapp_call_record!(existing_conversation)

        return existing_conversation
      end
    end

    # Create new conversation if no existing conversation found
    Rails.logger.info '[WHATSAPP_CALLS] No existing conversation found, creating new one for call'
    conversation = account.conversations.create!(
      contact: contact,
      inbox: inbox,
      contact_inbox: contact_inbox,
      identifier: @call_id,
      status: :open,
      additional_attributes: {
        'call_direction' => 'inbound',
        'call_status' => 'ringing',
        'call_id' => @call_id,
        'from_number' => @from_number,
        'to_number' => @to_number,
        'initiated_at' => Time.current.to_i,
        'has_active_call' => true,
        'sdp_offer' => @sdp_offer
      }.compact
    )

    # Crear registro de WhatsappCall
    create_whatsapp_call_record!(conversation)

    conversation
  end

  def pre_accept_call
    # Pre-accept to keep call active while agent decides
    Rails.logger.info "[WHATSAPP_CALLS] Pre-accepting incoming call #{@call_id}"

    # For pre-accept, we need to send a minimal SDP answer to WhatsApp
    # This keeps the call ringing without fully accepting it
    minimal_sdp = generate_minimal_sdp_answer

    api_adapter = Whatsapp::Calling::ApiAdapter.new(inbox.channel)
    result = api_adapter.pre_accept_call(call_id: @call_id, sdp_answer: minimal_sdp)

    if result[:success]
      Rails.logger.info "[WHATSAPP_CALLS] Call #{@call_id} pre-accepted, waiting for agent response"
    else
      Rails.logger.error "[WHATSAPP_CALLS] Pre-accept failed: #{result[:error]}"
      # If pre-accept fails, reject the call
      reject_call_on_error('Pre-accept failed')
    end
  rescue StandardError => e
    Rails.logger.error "[WHATSAPP_CALLS] Failed to pre-accept call: #{e.message}"
    reject_call_on_error(e.message)
  end

  def create_call_message!(conversation)
    # Crear el registro de WhatsappCall si no existe aún
    whatsapp_call = ensure_whatsapp_call_record!(conversation)

    # Crear mensaje de llamada iniciada usando CallMessageBuilder
    builder = Whatsapp::Calling::CallMessageBuilder.new(
      conversation: conversation,
      whatsapp_call: whatsapp_call
    )

    builder.create_initiated_message
  end

  def ensure_whatsapp_call_record!(conversation)
    whatsapp_call = WhatsappCall.find_or_initialize_by(call_id: @call_id)
    whatsapp_call.account ||= account
    whatsapp_call.conversation ||= conversation
    whatsapp_call.contact ||= conversation.contact
    whatsapp_call.inbox ||= inbox
    whatsapp_call.direction ||= 'inbound'
    # Ensure inbound calls enter the ringing state even if AASM defaulted to initiated
    whatsapp_call.status = 'ringing' if whatsapp_call.status.blank? || whatsapp_call.initiated?
    whatsapp_call.initiated_at ||= Time.current
    whatsapp_call.recording_enabled = @channel.calling_config&.fetch('recording_enabled', false) || false
    whatsapp_call.save!
    whatsapp_call
  end

  def create_whatsapp_call_record!(conversation)
    # Backward-compatible wrapper: ensure idempotency when duplicate webhooks arrive.
    ensure_whatsapp_call_record!(conversation)
  end

  def notify_agents(conversation)
    # Build call data payload
    # Frontend expects data wrapped in 'call' object (see whatsappCalls.js onIncomingCall)
    data = {
      account_id: account.id,
      call: {
        id: @call_id,
        call_id: @call_id,
        conversation_id: conversation.display_id,
        conversation_display_id: conversation.display_id,
        from_number: @from_number,
        contact_name: conversation.contact.name,
        contact_id: conversation.contact.id,
        status: 'ringing',
        direction: 'inbound',
        initiated_at: Time.current.to_i,
        sdp_offer: conversation.additional_attributes['sdp_offer']
      }
    }

    # If conversation is assigned to an agent, notify only that agent
    if conversation.assignee.present?
      Rails.logger.info "[WHATSAPP_CALLS] Notifying assigned agent: #{conversation.assignee.email}"

      # Create notification for assigned agent
      NotificationBuilder.new(
        notification_type: 'whatsapp_incoming_call',
        user: conversation.assignee,
        account: account,
        primary_actor: conversation,
        secondary_actor: nil
      ).perform

      # Also broadcast to agent's personal channel for real-time widget update
      ActionCable.server.broadcast(
        "user_#{conversation.assignee.id}",
        {
          event: 'whatsapp_incoming_call',
          data: data
        }
      )
    else
      # No assignee - broadcast to all online agents in the account
      # This allows any available agent to accept the call
      Rails.logger.info "[WHATSAPP_CALLS] Broadcasting incoming call to all agents in account #{account.id}"

      ActionCable.server.broadcast(
        "account_#{account.id}",
        {
          event: 'whatsapp_incoming_call',
          data: data
        }
      )
    end
  end

  def normalize_phone_number(phone)
    return phone if phone.blank?

    # Normalize to E.164: keep digits and ensure a leading +
    digits = phone.gsub(/\D/, '')
    return phone if digits.blank?

    "+#{digits}"
  end
end
