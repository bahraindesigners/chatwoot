require 'rails_helper'

RSpec.describe AutomationRules::InteractiveReplyService do
  let(:account) { create(:account) }
  let(:inbox) { create(:inbox, account: account, channel: create(:channel_whatsapp, account: account)) }
  let(:conversation) { create(:conversation, account: account, inbox: inbox) }
  let(:target) { create(:automation_rule, account: account, actions: [{ action_name: 'send_message', action_params: ['Next step'] }]) }
  let(:rule) { create(:automation_rule, account: account) }
  let(:payload) do
    { 'content' => 'Choose', 'items' => [{ 'title' => 'Same title', 'value' => 'language_ar',
                                         'next_step' => { 'automation_rule_id' => target.id } }] }
  end
  let(:flow) { AutomationRules::InteractiveFlowService.new(conversation, rule, 0) }
  let(:prepared) { flow.prepare(payload) }
  let(:menu) do
    create(:message, account: account, inbox: inbox, conversation: conversation, message_type: :outgoing,
                     content_type: :input_select, content_attributes: prepared.except('content'), source_id: 'outbound-id')
  end
  let(:reply) do
    create(:message, account: account, inbox: inbox, conversation: conversation, message_type: :incoming,
                     content: 'Same title', content_attributes: { interactive_reply_id: prepared['items'][0]['value'], in_reply_to: menu.id })
  end
  let(:action_service) { instance_double(AutomationRules::ActionService, perform: true) }

  before do
    flow.activate(menu)
    allow(AutomationRules::ActionService).to receive(:new).and_return(action_service)
  end

  it 'routes by the exact menu reply ID on the same conversation and claims it once' do
    expect(described_class.new(reply).perform).to be true
    expect(described_class.new(reply).perform).to be true
    expect(AutomationRules::ActionService).to have_received(:new).with(target, account, conversation, flow_depth: 1).once
    expect(action_service).to have_received(:perform).once
    expect(conversation.reload.additional_attributes['interactive_automation']['selected_value']).to eq('language_ar')
  end

  it 'ignores a different outbound context and never falls through to title matching' do
    reply.update!(content_attributes: reply.content_attributes.merge(in_reply_to_external_id: 'different-menu'))
    expect(described_class.new(reply).perform).to be true
    expect(action_service).not_to have_received(:perform)
  end

  it 'ignores an old menu after a newer menu replaces it' do
    reply
    newer = create(:message, account: account, inbox: inbox, conversation: conversation, message_type: :outgoing,
                             content_attributes: flow.prepare(payload).except('content'))
    flow.activate(newer)
    expect(described_class.new(reply).perform).to be true
    expect(action_service).not_to have_received(:perform)
  end

  it 'does not execute disabled source menus' do
    rule.update!(active: false)
    expect(described_class.new(reply).perform).to be true
    expect(action_service).not_to have_received(:perform)
  end

  it 'does not execute inactive targets' do
    target.update!(active: false)
    expect(described_class.new(reply).perform).to be true
    expect(action_service).not_to have_received(:perform)
  end

  it 'does not execute cross-account targets even when a saved menu has been tampered with' do
    other = create(:automation_rule)
    menu.content_attributes['interactive_automation']['routes'].values.first['next_step']['automation_rule_id'] = other.id
    menu.save!
    expect(described_class.new(reply).perform).to be true
    expect(action_service).not_to have_received(:perform)
  end

  it 'does not execute a source rule edited after sending the menu' do
    rule.update!(name: 'Edited')
    expect(described_class.new(reply).perform).to be true
    expect(action_service).not_to have_received(:perform)
  end

  it 'does not execute a target definition changed since the menu was sent' do
    target.update!(name: 'Changed target')
    expect(described_class.new(reply).perform).to be true
    expect(action_service).not_to have_received(:perform)
  end

  it 'records downstream action failure without repeating side effects' do
    allow(action_service).to receive(:perform).and_return(false)
    described_class.new(reply).perform
    described_class.new(reply).perform
    expect(action_service).to have_received(:perform).once
    expect(conversation.reload.additional_attributes['interactive_automation']['status']).to eq('failed')
  end

  it 'allows legacy values with the reserved-looking prefix when no routed menu owns them' do
    reply.update!(content_attributes: { interactive_reply_id: 'cwflow:legacy-value' })
    expect(described_class.new(reply).perform).to be false
  end

  it 'suppresses unknown generated-looking IDs without falling through to title rules' do
    reply.update!(content_attributes: { interactive_reply_id: "cwflow:#{'a' * 32}:#{'b' * 64}" })
    expect(described_class.new(reply).perform).to be true
  end

  it 'suppresses replies after the original routed menu is deleted' do
    reply
    menu.update!(content_type: :text, content_attributes: { deleted: true })
    expect(described_class.new(reply).perform).to be true
    expect(action_service).not_to have_received(:perform)
  end

  it 'preserves historical legacy menus with an exact generated-looking value' do
    value = "cwflow:#{'a' * 32}:#{'b' * 64}"
    create(:message, account: account, inbox: inbox, conversation: conversation, message_type: :outgoing,
                     content_type: :input_select, content_attributes: { items: [{ title: 'Legacy', value: value }] })
    reply.update!(content_attributes: { interactive_reply_id: value })
    expect(described_class.new(reply).perform).to be false
  end

  it 'preserves ordinary legacy replies' do
    reply.update!(content_attributes: { interactive_reply_id: 'legacy-value' })
    expect(described_class.new(reply).perform).to be false
    expect(action_service).not_to have_received(:perform)
  end
end
