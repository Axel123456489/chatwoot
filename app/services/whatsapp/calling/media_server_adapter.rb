# frozen_string_literal: true

require 'uri'

# Simplified adapter for generating SDP offers for WhatsApp calling
# Note: WhatsApp Cloud API handles actual media, this just generates valid SDP
class Whatsapp::Calling::MediaServerAdapter
  attr_reader :config, :candidate_host, :candidate_port

  def initialize
    @config = MediaServerConfig.media_server_config

    env_host = ENV.fetch('MEDIA_SERVER_PUBLIC_HOST', nil)
    config_host = @config['public_host']
    @candidate_host = env_host.presence || config_host.presence || '0.0.0.0'

    env_port = ENV.fetch('MEDIA_SERVER_PUBLIC_PORT', nil)
    config_port = @config['public_port']
    port_source = env_port.presence || config_port.presence
    @candidate_port = Integer(port_source || 50_000)

    Rails.logger.info("[MediaServer] Initialized with candidate_host=#{@candidate_host}, port=#{@candidate_port}")
  end

  # Generate SDP offer for WhatsApp calling
  # WhatsApp handles actual media, we just need a valid SDP structure
  def create_offer(audio_codec: 'opus', ice_servers: [])
    sdp_offer = generate_basic_sdp(audio_codec, ice_servers)

    unless validate_sdp(sdp_offer)
      Rails.logger.error('[MediaServer] Invalid SDP generated')
      return error_response('Invalid SDP structure')
    end

    Rails.logger.info("[MediaServer] Generated SDP offer (#{sdp_offer.lines.count} lines)")

    success_response(sdp: sdp_offer)
  rescue StandardError => e
    Rails.logger.error("[MediaServer] SDP generation error: #{e.message}")
    error_response(e.message)
  end

  private

  def validate_sdp(sdp)
    return false if sdp.blank?

    required_lines = ['v=', 'o=', 's=', 't=', 'm=audio']
    missing_lines = required_lines.reject { |line| sdp.include?(line) }

    if missing_lines.any?
      Rails.logger.error("[MediaServer] SDP missing required lines: #{missing_lines.join(', ')}")
      return false
    end

    true
  end

  def generate_basic_sdp(_audio_codec, ice_servers)
    # Generate session ID
    session_id = Time.now.to_i

    # Build ICE candidates from configured servers
    ice_candidates = build_ice_candidates(ice_servers)

    # Generate basic SDP structure for audio-only call
    lines = [
      'v=0',
      "o=- #{session_id} #{session_id} IN IP4 0.0.0.0",
      's=WhatsApp Audio Call',
      't=0 0',
      'a=group:BUNDLE audio',
      'a=msid-semantic: WMS chatwoot_audio_stream',
      'm=audio 9 UDP/TLS/RTP/SAVPF 111',
      'c=IN IP4 0.0.0.0',
      'a=rtcp:9 IN IP4 0.0.0.0',
      "a=ice-ufrag:#{SecureRandom.hex(8)}",
      "a=ice-pwd:#{SecureRandom.hex(12)}",
      "a=fingerprint:sha-256 #{generate_fingerprint}",
      'a=ice-options:trickle',
      'a=setup:actpass',
      'a=mid:audio',
      'a=sendrecv',
      'a=rtcp-mux',
      'a=ptime:20',
      'a=rtpmap:111 opus/48000/2',
      'a=fmtp:111 minptime=10;useinbandfec=1'
    ]

    "#{(lines + ice_candidates).join("\r\n")}\r\n"
  end

  def build_ice_candidates(ice_servers)
    ice_servers ||= []
    candidates = []
    candidates << "a=candidate:1 1 UDP 2130706431 #{candidate_host} #{candidate_port} typ host"

    ice_servers.each_with_index do |server, idx|
      urls = server['urls'] || server[:urls]
      server_ip = extract_ip_from_url(urls&.first || server['url'] || server[:url])
      next unless server_ip

      priority = 2_130_706_430 - idx
      port = 50_001 + idx
      candidates << "a=candidate:#{idx + 2} 1 UDP #{priority} #{server_ip} #{port} typ srflx"
    end

    candidates
  end

  def extract_ip_from_url(url)
    return nil unless url

    # Extract IP or hostname from STUN/TURN URL
    match = url.match(/(?:stun|turn):([^:]+)/)
    match ? match[1] : nil
  end

  def generate_fingerprint
    # Generate a random SHA-256 fingerprint for DTLS
    Array.new(20) { '%02X' % rand(256) }.join(':')
  end

  def success_response(data = {})
    { success: true }.merge(data)
  end

  def error_response(message)
    { success: false, error: message }
  end
end
