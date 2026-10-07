require 'json'
require 'time'
require 'securerandom'
require 'thread'
require 'ostruct'
class Object
  def present? = !nil? && (!respond_to?(:empty?) || !empty?)
  def blank? = !present?
end
class Array
  def pluck(key) = map { |item| item[key] }
end
module ActionController
  class Parameters < Hash; end
end
module Current
  def self.reset; end
end
class ChatwootExceptionTracker
  def initialize(*); end
  def capture_exception; end
end
module AutomationRules
  class ActionService
    class << self
      attr_accessor :calls, :result, :fail, :attributes
    end
    self.calls = 0
    self.result = true
    self.attributes = []
    def initialize(*) ; end
    def update_contact_attribute(params) = self.class.attributes << params
    def perform
      self.class.calls += 1
      raise 'simulated target failure' if self.class.fail
      self.class.result
    end
  end
end
class Collection
  attr_reader :records
  def initialize(records = []) = @records = records
  def active = Collection.new(records.select { |r| r.active })
  def outgoing = Collection.new(records.select(&:outgoing?))
  def where(criteria, *args)
    if criteria.is_a?(Hash)
      Collection.new(records.select { |r| criteria.all? { |key, val| r.public_send(key).to_s == val.to_s } })
    elsif criteria.include?('IS NULL')
      Collection.new(records.reject { |r| r.content_attributes.key?('interactive_automation') })
    else
      value = JSON.parse(args.first).dig('items', 0, 'value')
      Collection.new(records.select { |r| r.content_attributes.fetch('items', []).any? { |i| i['value'] == value } })
    end
  end
  def find_by(criteria) = where(criteria).records.first
  def find(id) = find_by(id: id) || raise('not found')
  def exists?(criteria = nil) = criteria ? !find_by(criteria).nil? : !records.empty?
end
class Menu
  attr_accessor :id, :content_attributes, :source_id, :content_type
  def initialize(id, attrs)
    @id, @content_attributes, @source_id, @content_type = id, attrs, "wa-#{id}", 'input_select'
  end
  def outgoing? = true
end
class Conversation
  attr_accessor :additional_attributes, :account, :messages, :inbox
  def initialize(account)
    @account, @additional_attributes, @messages, @lock = account, {}, Collection.new, Mutex.new
    @inbox = OpenStruct.new(channel_type: 'Channel::Whatsapp')
  end
  def with_lock(&block) = @lock.synchronize(&block)
  def update!(attrs) = @additional_attributes = attrs[:additional_attributes]
  def update_columns(attrs) = update!(attrs)
end
class Reply
  attr_accessor :content_attributes
  attr_reader :id, :conversation
  def initialize(id, conversation, reply_id, menu_id = nil)
    @id, @conversation, @content_attributes = id, conversation, { 'interactive_reply_id' => reply_id }
    @content_attributes['in_reply_to'] = menu_id if menu_id
  end
  def incoming? = true
end
# Runs only this script's isolated service doubles, never Rails or an external service.
root = ARGV.first || File.expand_path('..', __dir__)
require "#{root}/app/services/automation_rules/interactive_flow_service"
require "#{root}/app/services/automation_rules/interactive_action_validation_service"
require "#{root}/app/services/automation_rules/interactive_reply_service"
count = 0
assert = ->(value, description) { raise "FAILED: #{description}" unless value; count += 1; puts "PASS: #{description}" }
account = OpenStruct.new(automation_rules: Collection.new, custom_attribute_definitions: Collection.new)
source = OpenStruct.new(id: 1, active: true, updated_at: Time.utc(2026), execution_delay: nil, account: account)
target = OpenStruct.new(id: 2, active: true, updated_at: Time.utc(2026), execution_delay: nil, account: account)
account.automation_rules.records.concat([source, target])
conversation = Conversation.new(account)
payload = { 'content' => 'Choose', 'items' => [{ 'title' => 'Repeated title', 'value' => 'ar', 'next_step' => { 'automation_rule_id' => 2 } },
                                            { 'title' => 'Repeated title', 'value' => 'en' }] }
validator = AutomationRules::InteractiveActionValidationService.new([], account)
assert.call(validator.valid_next_step?(payload['items'][0]['next_step']), 'same-account target validates')
assert.call(!validator.valid_next_step?('automation_rule_id' => 99), 'unknown/cross-account target rejected')
target.active = false
assert.call(!validator.valid_next_step?('automation_rule_id' => 2), 'inactive target rejected')
target.active = true; target.execution_delay = 10
assert.call(!validator.valid_next_step?('automation_rule_id' => 2), 'delayed target rejected')
target.execution_delay = nil
assert.call(!validator.valid_next_step?('automation_rule_id' => '2'), 'malformed ID type rejected')
flow = AutomationRules::InteractiveFlowService.new(conversation, source, 0)
prepared = flow.prepare(payload)
assert.call(prepared['items'].pluck('value').uniq.size == 2, 'equal display titles have distinct wire identities')
assert.call(prepared['items'].all? { |i| i['value'].size < 200 }, 'provider IDs respect size bound')
assert.call(prepared['items'] != flow.prepare(payload)['items'], 'fresh menu gets distinct token')
legacy = { 'content' => 'Legacy', 'items' => [{ 'title' => 'Legacy', 'value' => 'legacy' }] }
assert.call(flow.prepare(legacy) == legacy, 'legacy payload unchanged')
menu = Menu.new(10, prepared.except('content')); conversation.messages.records << menu; flow.activate(menu)
reply = Reply.new(20, conversation, prepared['items'][0]['value'], menu.id)
assert.call(AutomationRules::InteractiveReplyService.new(reply).perform, 'configured click handled')
assert.call(AutomationRules::ActionService.calls == 1, 'target executed once')
assert.call(conversation.additional_attributes['interactive_automation']['selected_value'] == 'ar', 'stable configured value recorded')
AutomationRules::InteractiveReplyService.new(reply).perform
assert.call(AutomationRules::ActionService.calls == 1, 'duplicate click does not repeat action')
flow.activate(menu); target.updated_at += 1
AutomationRules::InteractiveReplyService.new(reply).perform
assert.call(AutomationRules::ActionService.calls == 1 && conversation.additional_attributes['interactive_automation']['status'] == 'unavailable', 'edited target suppressed')
target.updated_at -= 1; flow.activate(menu); source.updated_at += 1
AutomationRules::InteractiveReplyService.new(reply).perform
assert.call(AutomationRules::ActionService.calls == 1, 'edited source suppressed')
source.updated_at -= 1; flow.activate(menu)
reply.content_attributes['in_reply_to_external_id'] = 'wrong'
AutomationRules::InteractiveReplyService.new(reply).perform
assert.call(AutomationRules::ActionService.calls == 1, 'wrong outbound context suppressed')
reply.content_attributes.delete('in_reply_to_external_id'); flow.activate(menu)
AutomationRules::ActionService.fail = true
AutomationRules::InteractiveReplyService.new(reply).perform
AutomationRules::InteractiveReplyService.new(reply).perform
assert.call(AutomationRules::ActionService.calls == 2 && conversation.additional_attributes['interactive_automation']['status'] == 'failed', 'downstream failure durable and unrepeated')
AutomationRules::ActionService.fail = false
prefix_reply = Reply.new(21, conversation, 'cwflow:legacy')
assert.call(!AutomationRules::InteractiveReplyService.new(prefix_reply).perform, 'legacy prefix still falls through')
unknown_id = "cwflow:#{'a' * 32}:#{'b' * 64}"
unknown_reply = Reply.new(22, conversation, unknown_id)
assert.call(AutomationRules::InteractiveReplyService.new(unknown_reply).perform, 'unknown generated ID suppressed')
conversation.messages.records << Menu.new(11, { 'items' => [{ 'value' => unknown_id }] })
assert.call(!AutomationRules::InteractiveReplyService.new(unknown_reply).perform, 'historical exact-shape legacy menu recognized')
conversation.messages.records.clear
assert.call(AutomationRules::InteractiveReplyService.new(reply).perform, 'deleted routed menu remains replay-suppressed')
begin
  AutomationRules::InteractiveFlowService.new(conversation, source, 20).prepare(payload)
  raise 'limit not enforced'
rescue ArgumentError
  assert.call(true, 'chain limit enforced')
end
puts "#{count} isolated service assertions passed; no Rails/DB/integration coverage implied."
