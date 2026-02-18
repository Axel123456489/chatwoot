# frozen_string_literal: true

require 'openai'

# Shared OpenAI service base used by captain features that still rely on the OpenAI
# Ruby client (e.g., file uploads for assistants) while also exposing the RubyLLM
# chat helpers from Llm::BaseAiService.
class Llm::BaseOpenAiService < Llm::BaseAiService
  DEFAULT_MODEL = 'gpt-4o-mini'

  attr_reader :client, :model

  def initialize
    super()
    @client = build_openai_client
  end

  private

  def build_openai_client
    OpenAI::Client.new(
      access_token: InstallationConfig.find_by!(name: 'CAPTAIN_OPEN_AI_API_KEY').value,
      uri_base: openai_endpoint,
      log_errors: Rails.env.development?
    )
  end

  def openai_endpoint
    InstallationConfig.find_by(name: 'CAPTAIN_OPEN_AI_ENDPOINT')&.value.presence || 'https://api.openai.com/'
  end

  def setup_model
    config_value = InstallationConfig.find_by(name: 'CAPTAIN_OPEN_AI_MODEL')&.value
    @model = config_value.presence || DEFAULT_MODEL
  end
end
