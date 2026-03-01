module Whatsapp::IncomingMessageServiceHelpers
  def download_attachment_file(attachment_payload)
    Down.download(inbox.channel.media_url(attachment_payload[:id]), headers: inbox.channel.api_headers)
  end

  def conversation_params
    {
      account_id: @inbox.account_id,
      inbox_id: @inbox.id,
      contact_id: @contact.id,
      contact_inbox_id: @contact_inbox.id
    }
  end

  def processed_params
    @processed_params ||= params
  end

  def account
    @account ||= inbox.account
  end

  def message_type
    messages_data.first[:type]
  end

  def message_content(message)
    if message.dig(:text, :body)
      text = message.dig(:text, :body)
      ref = message[:referral]
      parts = [text]
      if ref.present?
        parts << "Referencia: #{ref[:source_url]}" if ref[:source_url].present?
        parts << "Tipo de referencia: #{ref[:source_type]}" if ref[:source_type].present?
        parts << "ID de referencia: #{ref[:source_id]}" if ref[:source_id].present?
      end
      final_content = parts.join("\n")
      return final_content
    end

    message.dig(:button, :text) ||
      message.dig(:interactive, :button_reply, :title) ||
      message.dig(:interactive, :list_reply, :title) ||
      message.dig(:name, :formatted_name)
  end

  def extract_button_reply_metadata(message)
    return nil unless message[:type].in?(%w[interactive button])

    if message[:type] == 'interactive'
      button_reply = message.dig(:interactive, :button_reply)
      list_reply = message.dig(:interactive, :list_reply)

      if button_reply.present?
        {
          from_button: true,
          button_type: 'button_reply',
          button_id: button_reply[:id],
          button_title: button_reply[:title]
        }
      elsif list_reply.present?
        {
          from_button: true,
          button_type: 'list_reply',
          button_id: list_reply[:id],
          button_title: list_reply[:title],
          list_description: list_reply[:description]
        }
      end
    elsif message[:type] == 'button'
      button = message[:button]
      {
        from_button: true,
        button_type: 'template_button',
        button_text: button[:text],
        button_payload: button[:payload]
      }
    end
  end

  def file_content_type(file_type)
    return :image if %w[image sticker].include?(file_type)
    return :audio if %w[audio voice].include?(file_type)
    return :video if ['video'].include?(file_type)
    return :location if ['location'].include?(file_type)
    return :contact if ['contacts'].include?(file_type)

    :file
  end

  def unprocessable_message_type?(message_type)
    %w[ephemeral unsupported request_welcome].include?(message_type)
  end

  # Handles a native WhatsApp call_permission_reply interactive message.
  # Creates an activity message summarising the outcome and updates the
  # WhatsappCallPermission record for this contact/inbox combination.
  def process_call_permission_reply(message)
    perm_data = message.dig(:interactive, :call_permission_reply)
    return unless perm_data

    response           = perm_data[:response].to_s          # "accept" / "deny"
    is_permanent       = perm_data[:is_permanent]
    expiration_ts      = perm_data[:expiration_timestamp]&.to_i
    contact_name       = @contact.name.presence || @contact.phone_number

    content = if response == 'accept'
                if is_permanent
                  "✅ #{contact_name} ha aceptado el permiso de llamada permanentemente."
                elsif expiration_ts
                  expires_str = Time.zone.at(expiration_ts).strftime('%d/%m/%Y')
                  "✅ #{contact_name} ha aceptado el permiso de llamada temporalmente (expira el #{expires_str})."
                else
                  "✅ #{contact_name} ha aceptado el permiso de llamada temporalmente."
                end
              else
                "❌ #{contact_name} ha rechazado el permiso de llamada."
              end

    # Find or create the permission record — the contact may have replied without
    # a prior request (e.g. directly from the WhatsApp UI).
    permission = Whatsapp::CallPermission.find_or_initialize_by(
      account: inbox.account,
      inbox: inbox,
      contact: @contact,
      phone_number_id: inbox.channel.phone_number_id
    )

    if response == 'accept'
      permission.assign_attributes(
        permission_status: 'granted',
        granted_at: Time.current,
        expires_at: expiration_ts ? Time.zone.at(expiration_ts) : nil,
        remaining_calls: 10
      )
    else
      permission.assign_attributes(permission_status: 'denied', remaining_calls: 0)
    end
    permission.save!

    @conversation.messages.create!(
      account_id: inbox.account_id,
      inbox_id: inbox.id,
      message_type: :activity,
      content: content
    )
  end

  def processed_waid(waid)
    Whatsapp::PhoneNumberNormalizationService.new(inbox).normalize_and_find_contact_by_provider(waid, :cloud)
  end

  def error_webhook_event?(message)
    message.key?('errors')
  end

  def log_error(message)
    Rails.logger.warn "Whatsapp Error: #{message['errors'][0]['title']} - contact: #{message['from']}"
  end

  def process_in_reply_to(message)
    @in_reply_to_external_id = message['context']&.[]('id')
  end

  def find_message_by_source_id(source_id)
    return unless source_id

    @message = Message.find_by(source_id: source_id)
  end

  def message_under_process?
    key = format(Redis::RedisKeys::MESSAGE_SOURCE_KEY, id: messages_data.first[:id])
    Redis::Alfred.get(key)
  end

  def cache_message_source_id_in_redis
    return if messages_data.blank?

    key = format(Redis::RedisKeys::MESSAGE_SOURCE_KEY, id: messages_data.first[:id])
    ::Redis::Alfred.setex(key, true)
  end

  def clear_message_source_id_from_redis
    key = format(Redis::RedisKeys::MESSAGE_SOURCE_KEY, id: messages_data.first[:id])
    ::Redis::Alfred.delete(key)
  end
end
