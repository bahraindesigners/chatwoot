class AutomationRules::InteractiveActionValidationService
  MAX_ITEMS = 10
  MAX_BUTTONS = 3
  PAYLOAD_KEYS = %w[content items list_button list_section].freeze
  ITEM_KEYS = %w[title value description next_step].freeze

  def initialize(actions, account)
    @actions = actions || []
    @account = account
  end

  def valid?
    @actions.is_a?(Array) && @actions.all? { |action| valid_action?(action) }
  rescue JSON::ParserError
    false
  end

  def valid_next_step?(step)
    return false unless step.is_a?(Hash) && (step.keys - %w[automation_rule_id contact_attribute]).empty?
    return false unless valid_destination?(step['automation_rule_id'])
    return true unless step.key?('contact_attribute')

    attribute = step['contact_attribute']
    attribute.is_a?(Hash) && attribute.keys.sort == %w[key value] &&
      valid_contact_attribute?([attribute['key'], attribute['value']])
  end

  private

  def valid_destination?(rule_id)
    rule_id.is_a?(Integer) && @account.automation_rules.active.where(execution_delay: nil).exists?(id: rule_id)
  end

  def reserved_legacy_ids?(items)
    items.none? { |item| item.key?('next_step') } &&
      items.any? { |item| AutomationRules::InteractiveFlowService::REPLY_ID_PATTERN.match?(item['value']) }
  end

  def valid_action?(action)
    return false unless action.is_a?(Hash) || action.is_a?(ActionController::Parameters)

    params = action[:action_params]
    case action[:action_name]
    when 'send_interactive_message'
      valid_message_params?(params)
    when 'update_contact_attribute'
      valid_contact_attribute?(params)
    else
      true
    end
  end

  def valid_message_params?(params)
    return false unless params.is_a?(Array) && params.length == 1 && params.first.is_a?(String)

    valid_message?(JSON.parse(params.first))
  end

  def valid_contact_attribute?(params)
    return false unless params.is_a?(Array) && params.length == 2 && params.all?(String)

    @account.custom_attribute_definitions.exists?(attribute_model: 'contact_attribute', attribute_display_type: 'text', attribute_key: params.first)
  end

  def valid_message?(payload)
    return false unless payload.is_a?(Hash) && (payload.keys - PAYLOAD_KEYS).empty?
    return false unless valid_text?(payload['content'], 1024) && valid_items?(payload['items'])

    list = list?(payload['items'])
    valid_list_field?(payload, 'list_button', 20, list) && valid_list_field?(payload, 'list_section', 24, list)
  end

  def valid_items?(items)
    return false unless valid_item_structure?(items)
    return false unless items.all? { |item| valid_item?(item, list?(items) ? 24 : 20) }

    return false if reserved_legacy_ids?(items)

    items.pluck('value').uniq.length == items.length
  end

  def valid_item_structure?(items)
    items.is_a?(Array) && items.length.between?(1, MAX_ITEMS) &&
      items.all? { |item| item.is_a?(Hash) && (item.keys - ITEM_KEYS).empty? }
  end

  def list?(items)
    items.length > MAX_BUTTONS || items.any? { |item| item.key?('description') }
  end

  def valid_list_field?(payload, key, limit, list)
    !payload.key?(key) || (list && valid_text?(payload[key], limit))
  end

  def valid_item?(item, title_limit)
    valid_text?(item['title'], title_limit) && valid_text?(item['value'], 200) &&
      (!item.key?('description') || valid_text?(item['description'], 72)) &&
      (!item.key?('next_step') || valid_next_step?(item['next_step']))
  end

  def valid_text?(value, limit)
    value.is_a?(String) && value.present? && value.length <= limit
  end
end
