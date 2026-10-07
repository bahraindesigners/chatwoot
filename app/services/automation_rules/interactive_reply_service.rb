class AutomationRules::InteractiveReplyService
  def initialize(message)
    @message = message
    @conversation = message.conversation
    @reply_id = message.content_attributes['interactive_reply_id']
  end

  def perform
    return false unless @message.incoming? && @conversation.inbox.channel_type == 'Channel::Whatsapp'
    return false unless managed_reply?

    # Claim and commit before side effects. Duplicate webhooks, old menus and second clicks
    # never fall through into title-based rules, even after this step is consumed.
    selection = claim_selection
    execute_selection(selection) if selection
    true
  rescue StandardError => e
    record_outcome('failed') if selection
    ChatwootExceptionTracker.new(e, account: @conversation.account).capture_exception
    true
  end

  private

  def managed_reply?
    return false unless @reply_id.is_a?(String) && AutomationRules::InteractiveFlowService::REPLY_ID_PATTERN.match?(@reply_id)

    # Historical legacy menus could use arbitrary values. Only an actual legacy menu
    # in this conversation can exempt a generated-looking ID from replay suppression.
    legacy_menu = @conversation.messages.outgoing.where(content_type: :input_select)
                               .where("content_attributes -> 'interactive_automation' IS NULL")
                               .exists?(['content_attributes::jsonb @> ?::jsonb', { items: [{ value: @reply_id }] }.to_json])
    !legacy_menu
  end

  def claim_selection
    @conversation.with_lock do
      state = @conversation.additional_attributes[AutomationRules::InteractiveFlowService::STATE_KEY]
      return unless available_state?(state)

      selection = selection_for(state)
      return unless selection

      state = state.merge('consumed_by' => @message.id, 'selected_value' => selection[:route]['value'], 'status' => 'claimed')
      # Internal flow bookkeeping must not generate another conversation automation event.
      # Direct internal state writes intentionally bypass callbacks to avoid recursive automation events.
      # rubocop:disable Rails/SkipsModelValidations
      @conversation.update_columns(additional_attributes: @conversation.additional_attributes.merge(
        AutomationRules::InteractiveFlowService::STATE_KEY => state
      ))
      # rubocop:enable Rails/SkipsModelValidations
      selection
    end
  end

  def available_state?(state)
    state && !state['consumed_by'] && current_definition?(state)
  end

  def selection_for(state)
    menu = @conversation.messages.outgoing.find_by(id: state['message_id'])
    flow = menu&.content_attributes&.[]('interactive_automation')
    route = flow&.dig('routes', @reply_id)
    return unless route && flow['token'] == state['token'] && valid_reply_context?(menu)

    { route: route, depth: flow['depth'].to_i + 1 }
  end

  def current_definition?(state)
    rule = @conversation.account.automation_rules.active.find_by(id: state['rule_id'])
    rule && rule.updated_at.iso8601(6) == state['rule_updated_at']
  end

  def valid_reply_context?(menu)
    attributes = @message.content_attributes
    return false if attributes['in_reply_to'].present? && attributes['in_reply_to'].to_i != menu.id

    attributes['in_reply_to_external_id'].blank? || attributes['in_reply_to_external_id'] == menu.source_id
  end

  def execute_selection(selection)
    step = selection[:route]['next_step']
    return record_outcome('completed') unless step
    return record_outcome('step_limit') if selection[:depth] >= AutomationRules::InteractiveFlowService::MAX_STEPS

    rule = destination_rule(selection, step)
    return record_outcome('unavailable') unless rule

    service = AutomationRules::ActionService.new(rule, @conversation.account, @conversation, flow_depth: selection[:depth])
    attribute = step['contact_attribute']
    service.send(:update_contact_attribute, [attribute.fetch('key'), attribute.fetch('value')]) if attribute
    record_outcome(service.perform ? 'completed' : 'failed')
  ensure
    Current.reset
  end

  def destination_rule(selection, step)
    # Revalidate at click time: a rule or attribute may have changed since the menu was sent.
    validator = AutomationRules::InteractiveActionValidationService.new([], @conversation.account)
    return unless validator.valid_next_step?(step)

    rule = @conversation.account.automation_rules.active.where(execution_delay: nil).find(step.fetch('automation_rule_id'))
    rule if rule.updated_at.iso8601(6) == selection[:route]['target_updated_at']
  end

  def record_outcome(status)
    @conversation.with_lock do
      state = @conversation.additional_attributes[AutomationRules::InteractiveFlowService::STATE_KEY]
      return unless state && state['consumed_by'] == @message.id

      # Direct internal state writes intentionally bypass callbacks to avoid recursive automation events.
      # rubocop:disable Rails/SkipsModelValidations
      @conversation.update_columns(additional_attributes: @conversation.additional_attributes.merge(
        AutomationRules::InteractiveFlowService::STATE_KEY => state.merge('status' => status)
      ))
      # rubocop:enable Rails/SkipsModelValidations
    end
  end
end
