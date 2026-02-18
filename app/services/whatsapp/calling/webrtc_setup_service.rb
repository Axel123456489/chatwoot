# frozen_string_literal: true

class Whatsapp::Calling::WebrtcSetupService
  def initialize(account:, inbox:, conversation:, call_id:, sdp_offer:)
    @account = account
    @inbox = inbox
    @channel = inbox.channel
    @conversation = conversation
    @call_id = call_id.presence || conversation&.additional_attributes&.dig('whatsapp_call', 'id')
    @sdp_offer = sdp_offer
  end

  def perform
    Rails.logger.info "[WEBRTC_SETUP] Starting P2P WebRTC setup for conversation #{@conversation.id}, call_id #{@call_id}"
    validate_inputs!
    ensure_calling_enabled!

    api_adapter = Whatsapp::Calling::ApiAdapter.new(@channel)
    Rails.logger.info "[WEBRTC_SETUP] Initiating WhatsApp call to #{normalize_phone_number(@conversation.contact.phone_number)}"

    begin
      response = api_adapter.initiate_call(
        to: normalize_phone_number(@conversation.contact.phone_number),
        sdp_offer: @sdp_offer
      )
      Rails.logger.info "[WEBRTC_SETUP] WhatsApp API response: #{response.inspect}"

      wa_call_id = extract_call_id(response)
      Rails.logger.info "[WEBRTC_SETUP] Extracted WhatsApp call_id: #{wa_call_id}"
      persist_call_state(wa_call_id)

      result = {
        success: true,
        call_id: wa_call_id
      }
      Rails.logger.info "[WEBRTC_SETUP] Returning result: success=true, call_id=#{wa_call_id}"
      result
    rescue StandardError => e
      Rails.logger.error("[WEBRTC_SETUP] Error: #{e.message}")
      raise
    end
  rescue StandardError => e
    Rails.logger.error("[WHATSAPP_CALLS] WebRTC setup failed: #{e.message}")
    Rails.logger.error("[WHATSAPP_CALLS] WebRTC setup error backtrace: #{e.backtrace.join("\n")}")
    { success: false, error: e.message }
  end

  def validate_inputs!
    raise StandardError, 'Conversation not found' unless @conversation
    raise StandardError, 'SDP offer missing' if @sdp_offer.blank?
  end

  def ensure_calling_enabled!
    return if @channel&.calling_enabled?

    raise StandardError, 'Calling is not enabled for this channel'
  end

  def extract_call_id(response)
    call_id = response.dig('calls', 0, 'id')
    raise StandardError, 'No call ID received from WhatsApp' unless call_id

    call_id
  end

  def persist_call_state(wa_call_id)
    attrs = (@conversation.additional_attributes || {}).deep_dup
    whatsapp_call = attrs['whatsapp_call'] || {}

    whatsapp_call['id'] = wa_call_id
    whatsapp_call['sdp_offer'] = @sdp_offer
    whatsapp_call['status'] = 'connecting'
    whatsapp_call['status_reason'] = 'awaiting_whatsapp_answer'
    whatsapp_call['direction'] ||= 'outbound'

    attrs['whatsapp_call'] = whatsapp_call
    # CRITICAL: Also store WhatsApp call_id at top level so terminate webhook can find it
    attrs['call_id'] = wa_call_id

    @conversation.update!(additional_attributes: attrs)

    # Create or update WhatsappCall record
    ensure_whatsapp_call_record(wa_call_id)
  end

  def ensure_whatsapp_call_record(wa_call_id)
    # CRITICAL: Look for existing WhatsappCall by conversation, not by wa_call_id
    # The call was created with a temporary call_id in /create endpoint
    # Now we need to update it with the real WhatsApp call_id
    whatsapp_call = WhatsappCall.for_conversation(@conversation.id)
                                .outbound
                                .recent
                                .first

    if whatsapp_call && whatsapp_call.call_id != wa_call_id
      ActiveRecord::Base.transaction do
        old_call_id = whatsapp_call.call_id
        whatsapp_call.update!(call_id: wa_call_id)

        # CRITICAL: Also update the message's call_metadata to use the new call_id
        # This ensures the terminate webhook can find the message later
        update_message_call_id(old_call_id, wa_call_id)
      end
    elsif !whatsapp_call
      # Check if recording is enabled
      recording_enabled = @channel.calling_config&.dig('recording_enabled') ||
                          Whatsapp::Calling::Configuration.recording_enabled?

      whatsapp_call = WhatsappCall.create!(
        account: @account,
        inbox: @inbox,
        contact: @conversation.contact,
        conversation: @conversation,
        call_id: wa_call_id,
        direction: 'outbound',
        status: 'initiated',
        initiated_at: Time.current,
        recording_enabled: recording_enabled,
        metadata: {
          browser_initiated: true,
          sdp_offer_sent: true
        }
      )
    end

    whatsapp_call
  end

  def update_message_call_id(old_call_id, new_call_id)
    message = @conversation.messages
                           .where(message_type: :activity, content_type: :voice_call)
                           .where("call_metadata->>'call_id' = ?", old_call_id)
                           .first

    return unless message

    metadata = message.call_metadata.merge('call_id' => new_call_id, 'whatsapp_call_sid' => new_call_id)
    message.update!(call_metadata: metadata)
  end

  def normalize_phone_number(phone)
    phone.to_s.gsub(/[^\d+]/, '')
  end
end
