require 'rails_helper'

RSpec.describe AutomationRules::InteractiveFlowService do
  let(:conversation) { create(:conversation) }
  let(:rule) { create(:automation_rule, account: conversation.account) }
  let(:payload) do
    { 'content' => 'Choose', 'items' => [
      { 'title' => 'Same title', 'value' => 'ar', 'next_step' => { 'automation_rule_id' => rule.id } },
      { 'title' => 'Same title', 'value' => 'en' }
    ] }
  end

  it 'keeps titles while generating bounded unique reply IDs and retaining configured values' do
    result = described_class.new(conversation, rule, 0).prepare(payload)
    expect(result['items'].pluck('title')).to eq(['Same title', 'Same title'])
    expect(result['items'].pluck('value').uniq.size).to eq(2)
    expect(result['items'].all? { |item| item['value'].length <= 200 && !item.key?('next_step') }).to be true
    expect(result['interactive_automation']['routes'].values.pluck('value')).to eq(%w[ar en])
  end

  it 'scopes the same configured options to each newly sent menu' do
    service = described_class.new(conversation, rule, 0)
    expect(service.prepare(payload)['items']).not_to eq(service.prepare(payload)['items'])
  end

  it 'preserves legacy wire IDs' do
    payload['items'].each { |item| item.delete('next_step') }
    expect(described_class.new(conversation, rule, 0).prepare(payload)).to eq(payload)
  end

  it 'bounds chained menus' do
    expect { described_class.new(conversation, rule, described_class::MAX_STEPS).prepare(payload) }.to raise_error(ArgumentError)
  end
end
