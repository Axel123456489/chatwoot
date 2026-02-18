# frozen_string_literal: true

# Service to handle SDP (Session Description Protocol) for WebRTC calls
# Generates SDP offers and processes SDP answers for WhatsApp calling
class Whatsapp::Calling::SdpHandlerService
  attr_reader :call_id, :conversation, :channel

  def initialize(call_id:, conversation:, channel:)
    @call_id = call_id
    @conversation = conversation
    @channel = channel
  end

  # Generate an SDP offer for WhatsApp calling
  def generate_offer
    return error_response('Media server not enabled') unless MediaServerConfig.enabled?

    begin
      # Generate SDP offer directly for WhatsApp
      sdp_offer = build_sdp_offer

      success_response(sdp_offer)
    rescue StandardError => e
      Rails.logger.error("[WhatsApp Call] SDP offer generation failed: #{e.message}")
      error_response("Failed to generate SDP offer: #{e.message}")
    end
  end

  def generate_outbound_offer
    Rails.logger.info("[WhatsApp Call] Generating outbound SDP offer for call #{call_id}")
    generate_offer
  end

  # Process SDP answer from WhatsApp (currently not needed for outbound calls)
  def process_answer(_sdp_answer)
    # For future implementation when handling bidirectional media
    success_response('SDP answer received')
  end

  private

  def build_sdp_offer
    media_server = Whatsapp::Calling::MediaServerAdapter.new

    # Generate SDP offer with configured audio codecs
    result = media_server.create_offer(
      audio_codec: MediaServerConfig.audio_codecs.first || 'opus',
      ice_servers: MediaServerConfig.ice_servers
    )

    raise "Failed to create offer: #{result[:error]}" unless result[:success]

    result[:sdp]
  end

  def success_response(data)
    { success: true, data: data }
  end

  def error_response(message)
    { success: false, error: message }
  end
end
