# frozen_string_literal: true

# Configuration loader for media server settings
module MediaServerConfig
  class << self
    def config
      @config ||= load_config
    end

    def enabled?
      config['enabled'] == true || config['enabled'] == 'true'
    end

    def provider
      config['provider']&.to_sym || :webrtc
    end

    def media_server_config
      config['media_server'] || {}
    end

    def ice_servers
      config['ice_servers'] || default_ice_servers
    end

    def audio_codecs
      config['audio_codecs'] || %w[opus pcmu pcma]
    end

    def max_call_duration
      (config['max_call_duration'] || 3600).to_i
    end

    def recording_enabled?
      config['recording_enabled'] == true || config['recording_enabled'] == 'true'
    end

    def recording_path
      config['recording_path'] || 'storage/call_recordings'
    end

    private

    def load_config
      config_file = Rails.root.join('config/media_server.yml')
      return {} unless File.exist?(config_file)

      # Process ERB template first, then parse YAML
      erb_content = ERB.new(File.read(config_file)).result
      yaml_config = YAML.safe_load(erb_content, aliases: true)
      yaml_config[Rails.env] || {}
    rescue StandardError => e
      Rails.logger.error("Failed to load media server config: #{e.message}")
      {}
    end

    def default_ice_servers
      [
        { 'urls' => 'stun:stun.l.google.com:19302' }
      ]
    end
  end
end
