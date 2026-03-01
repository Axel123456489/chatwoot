class Api::V1::Accounts::Contacts::WhatsappCallsController < Api::V1::Accounts::BaseController
  before_action :set_contact
  before_action :set_inbox
  before_action :validate_whatsapp_calling

  def create
    ActiveRecord::Base.transaction do
      @conversation = find_or_create_conversation

      # Initiate WhatsApp call through Meta API
      result = initiate_whatsapp_call

      if result[:success]
        # Create WhatsApp call record
        whatsapp_call = create_whatsapp_call_record(result)

        # Create call initiated message using the new builder
        message = Whatsapp::Calling::CallMessageBuilder.new(
          conversation: @conversation,
          whatsapp_call: whatsapp_call
        ).create_initiated_message

        render json: {
          conversation_id: @conversation.display_id,
          call_id: result[:call_id],
          message_id: message.id,
          message: 'WhatsApp call initiated successfully'
        }, status: :created
      else
        # Handle Meta API errors
        handle_call_error(result)
      end
    end
  rescue StandardError => e
    Rails.logger.error "[WHATSAPP_CALL] Error initiating call: #{e.message}"
    render json: { error: e.message }, status: :unprocessable_entity
  end

  private

  def set_contact
    @contact = Current.account.contacts.find(params[:id])
  end

  def set_inbox
    @inbox = Current.account.inboxes.find(params[:inbox_id])
    @channel = @inbox.channel
  rescue ActiveRecord::RecordNotFound
    render json: { error: 'Inbox not found' }, status: :not_found
  end

  def validate_whatsapp_calling
    return if @channel.is_a?(Channel::Whatsapp) && @channel.calling_enabled?

    render json: {
      error: 'WhatsApp calling is not enabled for this inbox'
    }, status: :unprocessable_entity
  end

  def find_or_create_conversation
    # Try to find existing open conversation
    conversation = @contact.conversations
                           .where(inbox: @inbox, status: [:open, :pending])
                           .last

    return conversation if conversation

    # Create new conversation
    # Use ContactInboxBuilder to properly sanitize source_id for WhatsApp
    contact_inbox_builder = ContactInboxBuilder.new(
      contact: @contact,
      inbox: @inbox,
      source_id: nil # Let builder generate it from contact.phone_number
    )
    contact_inbox_builder.perform

    contact_inbox = @contact.contact_inboxes.find_by(inbox: @inbox)

    Current.account.conversations.create!(
      contact: @contact,
      inbox: @inbox,
      contact_inbox: contact_inbox,
      status: :open,
      additional_attributes: {
        initiated_at: {
          timestamp: Time.current.to_i
        }
      }
    )
  end

  def initiate_whatsapp_call
    phone_number = params[:phone_number] || @contact.phone_number

    return { success: false, error: 'Contact phone number not found' } if phone_number.blank?

    # Generate a local call_id - the actual WhatsApp call will be initiated
    # when the browser sends its SDP offer via setup_webrtc
    call_id = "call-#{SecureRandom.hex(8)}"
    formatted_phone = phone_number.start_with?('+') ? phone_number : "+#{phone_number}"

    # Store initial call info in conversation
    # The browser will send its real SDP offer via setup_webrtc
    @conversation.additional_attributes ||= {}
    @conversation.additional_attributes['whatsapp_call'] = {
      'call_id' => call_id,
      'status' => 'awaiting_offer',
      'initiated_at' => Time.current.to_i,
      'phone_number' => formatted_phone
    }
    # Set root-level direction/status so the conversation list shows "Outgoing call" immediately
    @conversation.additional_attributes['call_direction'] = 'outbound'
    @conversation.additional_attributes['call_status'] = 'ringing'
    @conversation.save!

    { success: true, call_id: call_id, phone_number: formatted_phone, status: 'awaiting_offer' }
  rescue StandardError => e
    Rails.logger.error "[WHATSAPP_CALL] Error: #{e.message}"
    { success: false, error: e.message }
  end

  def create_whatsapp_call_record(result)
    WhatsappCall.create!(
      account: Current.account,
      conversation: @conversation,
      contact: @contact,
      inbox: @inbox,
      initiated_by_user: Current.user,
      call_id: result[:call_id],
      direction: 'outbound',
      initiated_at: Time.current,
      status: 'initiated'
    )
  end

  def handle_call_error(result)
    error_code = result[:error_code]
    error_message = result[:error] || 'Failed to initiate WhatsApp call'

    # Create a temporary WhatsappCall for the builder
    whatsapp_call = WhatsappCall.new(
      account: Current.account,
      conversation: @conversation,
      contact: @contact,
      inbox: @inbox,
      initiated_by_user: Current.user,
      call_id: "error-#{SecureRandom.hex(8)}",
      direction: 'outbound',
      initiated_at: Time.current,
      status: 'failed'
    )

    # Create error message
    Whatsapp::Calling::CallMessageBuilder.new(
      conversation: @conversation,
      whatsapp_call: whatsapp_call
    ).create_meta_error_message(
      error_code: error_code,
      error_message: error_message,
      meta_response: result[:meta_response]
    )

    render json: {
      error: error_message,
      error_code: error_code
    }, status: :unprocessable_entity
  end

  def create_call_message
    # This method is now deprecated - use CallMessageBuilder instead
    # Kept for backwards compatibility
    @conversation.messages.create!(
      message_type: :outgoing,
      content: "Outgoing WhatsApp call to #{@contact.name || @contact.phone_number}",
      content_type: 'voice_call',
      inbox: @inbox,
      account: Current.account,
      sender: Current.user,
      content_attributes: {
        data: {
          call_type: 'whatsapp',
          direction: 'outbound',
          status: 'ringing',
          initiated_at: Time.current.to_i
        }
      }
    )
  end
end
