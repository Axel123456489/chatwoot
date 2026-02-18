class Whatsapp::Calling::InitiateCallService
  pattr_initialize [:conversation!, :channel!, :user!]

  def perform
    return error_response('Calling not enabled') unless channel.calling_enabled?

    contact = conversation.contact
    permission = Whatsapp::CallPermission.find_by(
      account: conversation.account,
      inbox: conversation.inbox,
      contact: contact,
      phone_number_id: channel.phone_number_id
    )

    return error_response('No call permission found') unless permission&.can_make_call?

    # Make the API call to WhatsApp
    api_adapter = Whatsapp::Calling::ApiAdapter.new(channel)
    result = api_adapter.initiate_call(contact.phone_number)

    if result[:success]
      call_id = result[:call_id]

      # Store call information in conversation
      conversation.additional_attributes ||= {}
      conversation.additional_attributes['whatsapp_call'] = {
        'call_id' => call_id,
        'status' => 'initiated',
        'direction' => 'outbound',
        'initiated_by' => user.id,
        'initiated_at' => Time.current.to_s
      }
      conversation.save!

      # Create a message in the conversation
      conversation.messages.create!(
        account: conversation.account,
        inbox: conversation.inbox,
        sender: user,
        message_type: :activity,
        content: "📞 Outbound call initiated to #{contact.name}"
      )

      # Notify via ActionCable
      Rails.configuration.dispatcher.dispatch(
        CONVERSATION_UPDATED,
        Time.zone.now,
        conversation: conversation,
        user: user
      )

      success_response(call_id)
    else
      error_response(result[:error])
    end
  rescue StandardError => e
    Rails.logger.error("WhatsApp call initiation error: #{e.message}")
    Rails.logger.error(e.backtrace.join("\n"))
    error_response('Failed to initiate call')
  end

  private

  def success_response(call_id)
    { success: true, call_id: call_id }
  end

  def error_response(message)
    { success: false, error: message }
  end
end
