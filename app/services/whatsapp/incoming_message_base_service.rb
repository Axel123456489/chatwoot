# Mostly modeled after the intial implementation of the service based on 360 Dialog
# https://docs.360dialog.com/whatsapp-api/whatsapp-api/media
# https://developers.facebook.com/docs/whatsapp/api/media/
class Whatsapp::IncomingMessageBaseService
  include ::Whatsapp::IncomingMessageServiceHelpers

  pattr_initialize [:inbox!, :params!, :outgoing_echo]

  def perform
    processed_params

    if processed_params.try(:[], :statuses).present?
      process_statuses
    elsif messages_data.present?
      process_messages
    end
  end

  # Returns messages array for both regular messages and echo events
  def messages_data
    @processed_params&.dig(:messages) || @processed_params&.dig(:message_echoes)
  end

  private

  def process_messages
    # Handle reactions separately - they update existing messages
    if message_type == 'reaction'
      process_reaction
      return
    end

    # We don't support ephemeral message now, we need to skip processing the message
    # if the webhook event is an ephermal message or an unsupported message.
    if unprocessable_message_type?(message_type)
      WhatsappMessageError.create!(
        raw_payload: @processed_params,
        error_type: 'unsupported_type',
        error_message: "Tipo de mensaje no soportado: #{message_type}"
      )
      return
    end

    # Multiple webhook event can be received against the same message due to misconfigurations in the Meta
    # business manager account. While we have not found the core reason yet, the following line ensure that
    # there are no duplicate messages created.
    if find_message_by_source_id(messages_data.first[:id]) || message_under_process?
      WhatsappMessageError.create!(
        raw_payload: @processed_params,
        error_type: 'duplicate_or_processing',
        error_message: "Mensaje duplicado o en proceso: #{messages_data.first[:id]}"
      )
      return
    end

    cache_message_source_id_in_redis
    set_contact
    unless @contact
      WhatsappMessageError.create!(
        raw_payload: @processed_params,
        error_type: 'no_contact',
        error_message: 'No se pudo asociar el mensaje a un contacto válido.'
      )
      return
    end

    ActiveRecord::Base.transaction do
      set_conversation
      create_messages
      clear_message_source_id_from_redis
    end
  end

  def process_statuses
    return unless find_message_by_source_id(@processed_params[:statuses].first[:id])

    update_message_with_status(@message, @processed_params[:statuses].first)
  rescue ArgumentError => e
    Rails.logger.error "Error while processing whatsapp status update #{e.message}"
  end

  def process_reaction
    reaction_data = @processed_params[:messages].first[:reaction]
    return if reaction_data.blank?

    target_message_id = reaction_data[:message_id]
    emoji = reaction_data[:emoji]
    sender_wa_id = @processed_params[:messages].first[:from]

    target_message = inbox.messages.find_by(source_id: target_message_id)
    return unless target_message

    reactions = target_message.content_attributes['reactions'] || {}

    if emoji.present?
      reactions[sender_wa_id] = {
        'emoji' => emoji,
        'timestamp' => @processed_params[:messages].first[:timestamp].to_i,
        'user_type' => 'customer'
      }
    else
      reactions.delete(sender_wa_id)
    end

    target_message.update!(content_attributes: target_message.content_attributes.merge('reactions' => reactions))
  rescue StandardError => e
    Rails.logger.error "[WhatsApp] Error processing reaction: #{e.message}"
  end

  def update_message_with_status(message, status)
    message.status = status[:status]
    if status[:status] == 'failed' && status[:errors].present?
      error = status[:errors]&.first
      message.external_error = "#{error[:code]}: #{error[:title]}"
    end
    message.save!
  end

  def create_messages
    message = messages_data.first
    if error_webhook_event?(message)
      WhatsappMessageError.create!(
        raw_payload: @processed_params,
        error_type: 'webhook_error',
        error_message: message['errors'].try(:first).try(:[], 'title') || 'Error en el webhook.'
      )
      log_error(message)
      return
    end

    process_in_reply_to(message)

    # Handle native WhatsApp call permission replies specially — they carry no
    # displayable text content of their own, so skip the regular message and
    # instead create a human-readable activity message + update the permission record.
    if message_type == 'interactive' && message.dig(:interactive, :type) == 'call_permission_reply'
      process_call_permission_reply(message)
      return
    end

    message_type == 'contacts' ? create_contact_messages(message) : create_regular_message(message)
  end

  def create_contact_messages(message)
    message['contacts'].each do |contact|
      # Pass source_id from parent message since contact objects don't have :id
      create_message(contact, source_id: message[:id])
      attach_contact(contact)
      @message.save!
    end
  end

  def create_regular_message(message)
    create_message(message, source_id: message[:id])

    # Convertimos a hash con acceso indiferente para evitar problemas con claves string/símbolo
    message = message.with_indifferent_access

    begin
      Rails.logger.info "📦 Mensaje recibido: #{message.inspect}"

      referral_image_url = message.dig(:referral, :image_url)
      Rails.logger.info "🔍 referral_image_url detectado: #{referral_image_url.inspect}"

      if referral_image_url.present? && referral_image_url =~ URI::DEFAULT_PARSER.make_regexp
        Rails.logger.info "📸 Descargando imagen desde referral: #{referral_image_url}"

        begin
          file_uri = URI.parse(referral_image_url)
          downloaded_file = URI.open(file_uri)

          raise 'Archivo descargado está vacío' if downloaded_file.blank?

          @message.attachments.new(
            account_id: @message.account_id,
            file_type: :image,
            file: {
              io: downloaded_file,
              filename: File.basename(file_uri.path),
              content_type: downloaded_file.content_type || 'image/png'
            },
            fallback_title: 'Imagen referida desde campaña'
          )

          Rails.logger.info '✅ Imagen descargada y adjuntada exitosamente'

        rescue StandardError => e
          Rails.logger.error "❌ Error al procesar imagen del referral: #{e.message}\n#{e.backtrace.join("\n")}"

          # ⚠️ Mensaje visible si falla la imagen
          @message.content = "#{@message.content}\n⚠️ Imagen de campaña no disponible." if @message.content.present?
          @message.content ||= '⚠️ Imagen de campaña no disponible.'
        end

      else
        Rails.logger.warn "⚠️ URL de imagen no válida o no presente en referral: #{referral_image_url.inspect}"
      end
    rescue StandardError => e
      Rails.logger.error "❌ Error inesperado al agregar imagen desde referral: #{e.message}\n#{e.backtrace.join("\n")}"
    end

    attach_files
    attach_location if message_type == 'location'
    @message.save!
  end

  def set_contact
    if outgoing_echo
      set_contact_from_echo
    else
      set_contact_from_message
    end
  end

  def set_contact_from_echo
    # For echo messages, contact phone is in the 'to' field
    phone_number = messages_data.first[:to]
    waid = processed_waid(phone_number)

    contact_inbox = ::ContactInboxWithContactBuilder.new(
      source_id: waid,
      inbox: inbox,
      contact_attributes: { name: "+#{phone_number}", phone_number: "+#{phone_number}" }
    ).perform

    @contact_inbox = contact_inbox
    @contact = contact_inbox.contact
  end

  def set_contact_from_message
    contact_params = @processed_params[:contacts]&.first
    return if contact_params.blank?

    waid = processed_waid(contact_params[:wa_id])

    contact_inbox = ::ContactInboxWithContactBuilder.new(
      source_id: waid,
      inbox: inbox,
      contact_attributes: { name: contact_params.dig(:profile, :name), phone_number: "+#{messages_data.first[:from]}" }
    ).perform

    @contact_inbox = contact_inbox
    @contact = contact_inbox.contact

    # Update existing contact name if ProfileName is available and current name is just phone number
    update_contact_with_profile_name(contact_params)
  end

  def set_conversation
    # if lock to single conversation is disabled, we will create a new conversation if previous conversation is resolved
    @conversation = if @inbox.lock_to_single_conversation
                      @contact_inbox.conversations.last
                    else
                      @contact_inbox.conversations
                                    .where.not(status: :resolved).last
                    end
    return if @conversation

    @conversation = ::Conversation.create!(conversation_params)
  end

  def attach_files
    return if %w[text button interactive location contacts].include?(message_type)

    attachment_payload = messages_data.first[message_type.to_sym]
    @message.content ||= attachment_payload[:caption]

    attachment_file = download_attachment_file(attachment_payload)
    return if attachment_file.blank?

    @message.attachments.new(
      account_id: @message.account_id,
      file_type: file_content_type(message_type),
      file: {
        io: attachment_file,
        filename: attachment_file.original_filename,
        content_type: attachment_file.content_type
      }
    )
  end

  def attach_location
    location = messages_data.first['location']
    location_name = location['name'] ? "#{location['name']}, #{location['address']}" : ''
    @message.attachments.new(
      account_id: @message.account_id,
      file_type: file_content_type(message_type),
      coordinates_lat: location['latitude'],
      coordinates_long: location['longitude'],
      fallback_title: location_name,
      external_url: location['url']
    )
  end

  def create_message(message, source_id: nil)
    content_attrs = outgoing_echo ? { external_echo: true } : {}
    content_attrs[:in_reply_to_external_id] = @in_reply_to_external_id if @in_reply_to_external_id.present?

    # Extract button reply metadata if present
    button_metadata = extract_button_reply_metadata(message)
    content_attrs.merge!(button_metadata) if button_metadata.present?

    @message = @conversation.messages.build(
      content: message_content(message),
      account_id: @inbox.account_id,
      inbox_id: @inbox.id,
      message_type: outgoing_echo ? :outgoing : :incoming,
      # Set status to :delivered for echo messages to prevent SendReplyJob from trying to send them
      status: outgoing_echo ? :delivered : :sent,
      sender: outgoing_echo ? nil : @contact,
      source_id: (source_id || message[:id]).to_s,
      content_attributes: content_attrs
    )
  end

  def attach_contact(contact)
    phones = contact[:phones]
    phones = [{ phone: 'Phone number is not available' }] if phones.blank?

    name_info = contact['name'] || {}
    contact_meta = {
      firstName: name_info['first_name'],
      lastName: name_info['last_name']
    }.compact

    phones.each do |phone|
      @message.attachments.new(
        account_id: @message.account_id,
        file_type: file_content_type(message_type),
        fallback_title: phone[:phone].to_s,
        meta: contact_meta
      )
    end
  end

  def update_contact_with_profile_name(contact_params)
    profile_name = contact_params.dig(:profile, :name)
    return if profile_name.blank?
    return if @contact.name == profile_name

    # Only update if current name exactly matches the phone number or formatted phone number
    return unless contact_name_matches_phone_number?

    @contact.update!(name: profile_name)
  end

  def contact_name_matches_phone_number?
    phone_number = "+#{messages_data.first[:from]}"
    formatted_phone_number = TelephoneNumber.parse(phone_number).international_number
    @contact.name == phone_number || @contact.name == formatted_phone_number
  end
end
