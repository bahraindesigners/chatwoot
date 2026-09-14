# frozen_string_literal: true

require 'agents'

Rails.application.config.after_initialize do
  api_key = InstallationConfig.find_by(name: 'CAPTAIN_OPEN_AI_API_KEY')&.value
  model = InstallationConfig.find_by(name: 'CAPTAIN_OPEN_AI_MODEL')&.value.presence || LlmConstants::DEFAULT_MODEL
  api_endpoint = InstallationConfig.find_by(name: 'CAPTAIN_OPEN_AI_ENDPOINT')&.value || LlmConstants::OPENAI_API_ENDPOINT

  if api_key.present?
    Agents.configure do |config|
      Llm::Config.configure_agents(config, api_key: api_key, api_endpoint: api_endpoint)
      config.default_model = model
      config.debug = false
    end

    RubyLLM.configure do |config|
      Llm::Config.configure_provider(config, api_key: api_key, api_endpoint: api_endpoint)
    end
  end
rescue StandardError => e
  Rails.logger.error "Failed to configure AI Agents SDK: #{e.message}"
end
