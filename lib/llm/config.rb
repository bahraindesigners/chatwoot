require 'ruby_llm'
require 'uri'

module Llm::Config
  DEFAULT_MODEL = 'gpt-4.1-mini'.freeze
  DEFAULT_API_ENDPOINT = 'https://api.openai.com'.freeze
  PROVIDER_HOSTS = {
    'openrouter.ai' => 'openrouter'
  }.freeze

  class << self
    def initialized?
      @initialized ||= false
    end

    def initialize!
      return if @initialized

      configure_ruby_llm
      @initialized = true
    end

    def reset!
      @initialized = false
    end

    def with_api_key(api_key, api_base: nil)
      initialize!
      context = RubyLLM.context do |config|
        configure_provider(config, api_key: api_key, api_endpoint: api_base)
      end

      yield context
    end

    def provider_for(api_endpoint = nil)
      host = URI.parse(api_endpoint.presence || openai_endpoint).host&.downcase
      PROVIDER_HOSTS.fetch(host, 'openai')
    end

    def configure_agents(config, api_key:, api_endpoint:)
      endpoint = api_endpoint.presence || DEFAULT_API_ENDPOINT
      provider = provider_for(endpoint)

      config.openai_api_key = api_key
      config.openai_api_base = openai_compatible_api_base(endpoint)
      config.public_send("#{provider}_api_key=", api_key) unless provider == 'openai'
    end

    def configure_provider(config, api_key:, api_endpoint:)
      endpoint = api_endpoint.presence || DEFAULT_API_ENDPOINT
      provider = provider_for(endpoint)

      config.openai_api_key = api_key
      config.openai_api_base = openai_compatible_api_base(endpoint)
      config.openai_use_system_role = provider != 'openai'

      return if provider == 'openai'

      config.public_send("#{provider}_api_key=", api_key)
      config.public_send("#{provider}_api_base=", provider_api_base(provider, endpoint))
    end

    private

    def configure_ruby_llm
      RubyLLM.configure do |config|
        configure_provider(config, api_key: system_api_key, api_endpoint: openai_endpoint) if system_api_key.present?
        config.model_registry_file = Rails.root.join('config/llm_models.json').to_s
        config.logger = Rails.logger
      end
    end

    def openai_compatible_api_base(endpoint)
      base = endpoint.chomp('/')
      base.end_with?('/v1') ? base : "#{base}/v1"
    end

    def provider_api_base(provider, endpoint)
      return openai_compatible_api_base(endpoint) if provider == 'openrouter'

      endpoint.chomp('/')
    end

    def system_api_key
      InstallationConfig.find_by(name: 'CAPTAIN_OPEN_AI_API_KEY')&.value
    end

    def openai_endpoint
      InstallationConfig.find_by(name: 'CAPTAIN_OPEN_AI_ENDPOINT')&.value.presence || DEFAULT_API_ENDPOINT
    end
  end
end
