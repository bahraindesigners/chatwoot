# frozen_string_literal: true

require 'json'

module Llm::Providers::DeepseekChatCompatibility
  private

  # rubocop:disable Metrics/ParameterLists
  def render_payload(messages, tools:, temperature:, model:, stream: false, schema: nil, thinking: nil, tool_prefs: nil)
    payload = super
    return payload unless schema

    payload[:response_format] = { type: 'json_object' }
    append_json_schema_instruction(payload[:messages], schema)
    payload
  end
  # rubocop:enable Metrics/ParameterLists

  def append_json_schema_instruction(messages, schema)
    instruction = "Return only a valid JSON object matching this JSON Schema:\n#{JSON.generate(schema.fetch(:schema))}"
    system_message = messages.find { |message| message[:role] == 'system' }

    if system_message
      system_message[:content] = "#{system_message[:content]}\n\n#{instruction}"
    else
      messages.unshift(role: 'system', content: instruction)
    end
  end
end

RubyLLM::Providers::DeepSeek.prepend(Llm::Providers::DeepseekChatCompatibility)
