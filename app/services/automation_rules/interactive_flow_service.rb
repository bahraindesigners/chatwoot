require 'digest'

# Menu identity is distinct from translated display titles and scoped to one conversation step.
class AutomationRules::InteractiveFlowService
  STATE_KEY = 'interactive_automation'.freeze
  REPLY_PREFIX = 'cwflow:'.freeze
  REPLY_ID_PATTERN = /\Acwflow:([0-9a-f]{32}):[0-9a-f]{64}\z/
  MAX_STEPS = 20

  def initialize(conversation, rule, depth)
    @conversation = conversation
    @rule = rule
    @depth = depth
  end

  def prepare(payload)
    return payload unless payload.fetch('items').any? { |item| item.key?('next_step') }

    raise ArgumentError, 'Interactive automation exceeded its step limit' if @depth >= MAX_STEPS

    token = SecureRandom.hex(16)
    routes = {}
    items = payload.fetch('items').map do |item|
      reply_id = "#{REPLY_PREFIX}#{token}:#{Digest::SHA256.hexdigest(item.fetch('value'))}"
      routes[reply_id] = route_snapshot(item)
      item.except('next_step').merge('value' => reply_id)
    end
    payload.merge('items' => items, 'interactive_automation' => { 'token' => token, 'depth' => @depth, 'routes' => routes })
  end

  def activate(message)
    # A new legacy menu also replaces any previous routed menu.
    state = message.content_attributes['interactive_automation']
    @conversation.with_lock do
      attributes = @conversation.additional_attributes.except(STATE_KEY)
      if state
        attributes[STATE_KEY] = state.except('routes').merge(
          'message_id' => message.id, 'rule_id' => @rule.id, 'rule_updated_at' => @rule.updated_at.iso8601(6)
        )
      end
      @conversation.update!(additional_attributes: attributes)
    end
  end

  private

  def route_snapshot(item)
    step = item['next_step']
    target = @rule.account.automation_rules.find_by(id: step['automation_rule_id']) if step
    { 'value' => item.fetch('value'), 'next_step' => step, 'target_updated_at' => target&.updated_at&.iso8601(6) }
  end
end
