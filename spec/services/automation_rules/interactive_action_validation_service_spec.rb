require 'rails_helper'

RSpec.describe AutomationRules::InteractiveActionValidationService do
  let(:account) { create(:account) }
  let(:target) { create(:automation_rule, account: account) }
  let(:step) { { 'automation_rule_id' => target.id } }
  let(:payload) { { content: 'Choose', items: [{ title: 'Arabic', value: 'ar', next_step: step }] } }
  let(:actions) { [{ action_name: 'send_interactive_message', action_params: [payload.to_json] }].map(&:with_indifferent_access) }

  it 'accepts an active same-account next step' do
    expect(described_class.new(actions, account).valid?).to be true
  end

  it 'rejects an automation from another account' do
    step['automation_rule_id'] = create(:automation_rule).id
    expect(described_class.new(actions, account).valid?).to be false
  end

  it 'rejects inactive or delayed targets' do
    target.update!(active: false)
    expect(described_class.new(actions, account).valid?).to be false
    target.update!(active: true, event_name: 'message_created', execution_delay: 10)
    expect(described_class.new(actions, account).valid?).to be false
  end

  it 'accepts an existing contact text attribute and an empty value for clearing it' do
    attribute = create(:custom_attribute_definition, account: account, attribute_model: 'contact_attribute', attribute_display_type: 'text')
    step['contact_attribute'] = { 'key' => attribute.attribute_key, 'value' => '' }
    expect(described_class.new(actions, account).valid?).to be true
  end

  it 'rejects arbitrary contact attributes and unexpected next-step data' do
    step['contact_attribute'] = { 'key' => 'missing', 'value' => 'ar' }
    expect(described_class.new(actions, account).valid?).to be false
    step.delete('contact_attribute')
    step['actions'] = []
    expect(described_class.new(actions, account).valid?).to be false
  end

  it 'preserves legacy messages without next steps' do
    payload[:items].first.delete(:next_step)
    expect(described_class.new(actions, account).valid?).to be true
  end
end
