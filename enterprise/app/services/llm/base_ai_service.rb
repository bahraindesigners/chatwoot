# frozen_string_literal: true

# Base service for LLM operations using RubyLLM.
# New features should inherit from this class.
class Llm::BaseAiService
  DEFAULT_MODEL = Llm::Config::DEFAULT_MODEL
  DEFAULT_TEMPERATURE = 1.0

  attr_reader :model, :provider, :temperature

  def initialize(feature: nil, account: nil, fallback_model: nil)
    @llm_feature = feature
    @llm_account = account
    @fallback_model = fallback_model

    Llm::Config.initialize!
    setup_model
    setup_temperature
  end

  def chat(model: @model, temperature: @temperature)
    options = { model: model }
    if @provider
      options[:provider] = @provider
      options[:assume_model_exists] = @assume_model_exists
    end

    RubyLLM.chat(**options).with_temperature(temperature)
  end

  private

  # Strips markdown code fences (```json ... ``` or ``` ... ```) that some
  # LLM providers/gateways wrap around JSON responses despite response_format hints.
  def sanitize_json_response(response)
    return response if response.nil?

    response.strip.sub(/\A```(?:\w*)\s*\n?/, '').sub(/\n?\s*```\s*\z/, '').strip
  end

  def setup_model
    route = feature_route
    return apply_model_route(route) if account_override_route?(route) || installation_override_route?(route) || captain_v2_assistant?

    if @fallback_model.present?
      return apply_model_route(model: @fallback_model, provider: Llm::Models.provider_for(@fallback_model), source: :fallback)
    end

    if installation_model.present?
      return apply_model_route(
        model: installation_model,
        provider: Llm::Config.provider_for,
        source: :installation_override
      )
    end

    apply_model_route(route || { model: DEFAULT_MODEL, provider: Llm::Models.provider_for(DEFAULT_MODEL), source: :default })
  end

  def feature_route
    return if @llm_feature.blank?

    Llm::FeatureRouter.resolve(feature: @llm_feature, account: @llm_account)
  end

  def account_override_route?(route)
    route&.dig(:source) == :account_override
  end

  def installation_override_route?(route)
    route&.dig(:source) == :installation_override
  end

  def captain_v2_assistant?
    @llm_feature.to_s == 'assistant' && @llm_account&.feature_enabled?('captain_integration_v2')
  end

  def installation_model
    InstallationConfig.find_by(name: 'CAPTAIN_OPEN_AI_MODEL')&.value
  end

  def apply_model_route(route)
    @model = route[:model]
    if route[:source] == :installation_override
      @provider = route[:provider]
      @assume_model_exists = true
    end
    @model
  end

  def setup_temperature
    @temperature = DEFAULT_TEMPERATURE
  end
end
