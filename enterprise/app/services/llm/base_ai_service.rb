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

  def chat(model: @model, temperature: @temperature, thinking: nil, feature: @llm_feature, **)
    options = Captain::ResponsesConfig.options(model: model, temperature: temperature, feature: feature)
    thinking ||= options[:thinking]
    provider_options = @provider ? { provider: @provider, assume_model_exists: @assume_model_exists } : {}
    llm_chat = RubyLLM.chat(model: model, **options.slice(:protocol), **provider_options, **)
    llm_chat.with_thinking(**thinking) if thinking
    return llm_chat if options[:temperature].nil? || (thinking && thinking[:effort] != :none)

    llm_chat.with_temperature(options[:temperature])
  end

  def json_chat(model: @model, feature: @llm_feature, temperature: @temperature)
    llm_chat = chat(model: model, feature: feature, temperature: temperature)
    options = Captain::ResponsesConfig.options(model: model, temperature: temperature, feature: feature)
    format = { type: 'json_object' }
    # Responses JSON mode requires a JSON instruction in input, even when instructions already specify the output format.
    llm_chat.add_message(role: :user, content: 'Respond with valid JSON.') if options[:protocol] == :responses
    llm_chat.with_provider_options(Captain::ResponsesConfig.json_format_options(protocol: options[:protocol], format: format))
  end

  private

  def llm_instrumentation_params(params)
    feature = params[:llm_feature] || @llm_feature
    options = Captain::ResponsesConfig.options(model: params[:model], temperature: params[:temperature], feature: feature)
    metadata = Captain::ResponsesConfig.request_metadata(model: params[:model], feature: feature)
    params.merge(temperature: options[:temperature], metadata: params[:metadata].to_h.merge(metadata))
  end

  # Strips markdown code fences (```json ... ``` or ``` ... ```) that some
  # LLM providers/gateways wrap around JSON responses despite response_format hints.
  def sanitize_json_response(response)
    return response if response.nil?

    response.strip.sub(/\A```(?:\w*)\s*\n?/, '').sub(/\n?\s*```\s*\z/, '').strip
  end

  def setup_model
    route = feature_route
    return apply_model_route(route) if account_override_route?(route) || installation_override_route?(route) || captain_assistant?

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

  def captain_assistant?
    @llm_feature.to_s == 'assistant' && @llm_account&.feature_enabled?('captain_integration')
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
