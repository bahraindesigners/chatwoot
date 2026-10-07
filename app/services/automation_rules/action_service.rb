class AutomationRules::ActionService < ActionService
  def initialize(rule, account, conversation, flow_depth: 0)
    super(conversation)
    @flow_depth = flow_depth
    @rule = rule
    @account = account
    @reply_messages = []
    Current.executed_by = rule
  end

  def perform
    failed = false
    @rule.actions.each do |action|
      @conversation.reload
      action = action.with_indifferent_access
      begin
        send(action[:action_name], action[:action_params])
      rescue StandardError => e
        failed = true
        ChatwootExceptionTracker.new(e, account: @account).capture_exception
      end
    end
    !failed
  ensure
    Current.reset
    enqueue_whatsapp_replies
  end

  private

  def build_reply(params)
    if @conversation.inbox.channel_type == 'Channel::Whatsapp'
      attributes = params[:content_attributes] || {}
      params[:content_attributes] = attributes.merge(automation_rule_id: @rule.id, automation_reply_batch: true)
    end
    message = Messages::MessageBuilder.new(nil, @conversation, params).perform
    @reply_messages << message
    message
  end

  def enqueue_whatsapp_replies
    return if @reply_messages.empty? || @conversation.inbox.channel_type != 'Channel::Whatsapp'

    # Preserve Active Storage's upload delay, then send the rule's replies in action order.
    job = if @reply_messages.any? { |message| message.attachments.present? }
            AutomationRules::SendReplyBatchJob.set(wait: 2.seconds)
          else
            AutomationRules::SendReplyBatchJob
          end
    job.perform_later(@reply_messages.map(&:id))
  end

  def send_attachment(blob_ids)
    return if conversation_a_tweet?

    return unless @rule.files.attached?

    blobs = ActiveStorage::Blob.where(id: blob_ids)

    return if blobs.blank?

    params = { content: nil, private: false, attachments: blobs }
    build_reply(params)
  end

  def send_webhook_event(webhook_url)
    payload = @conversation.webhook_data.merge(event: "automation_event.#{@rule.event_name}")
    WebhookJob.perform_later(webhook_url[0], payload)
  end

  def send_interactive_message(params)
    payload = JSON.parse(params.fetch(0))
    flow = AutomationRules::InteractiveFlowService.new(@conversation, @rule, @flow_depth)
    payload = flow.prepare(payload)
    attributes = payload.except('content').merge(automation_rule_id: @rule.id).with_indifferent_access
    message_params = ActionController::Parameters.new(
      content: payload.fetch('content'), content_type: 'input_select', private: false, content_attributes: attributes
    )
    message = build_reply(message_params)
    flow.activate(message)
  end

  def update_contact_attribute(params)
    contact = @conversation.contact
    attributes = contact.custom_attributes.merge(params.fetch(0) => params.fetch(1))
    attributes.delete(params.fetch(0)) if params.fetch(1).empty?
    contact.update!(custom_attributes: attributes)
  end

  def send_message(message)
    return if conversation_a_tweet?

    params = { content: message[0], private: false, content_attributes: { automation_rule_id: @rule.id } }
    build_reply(params)
  end

  def add_private_note(message)
    return if conversation_a_tweet?

    params = { content: message[0], private: true, content_attributes: { automation_rule_id: @rule.id } }
    Messages::MessageBuilder.new(nil, @conversation.reload, params).perform
  end

  def send_email_to_team(params)
    teams = Team.where(id: params[0][:team_ids])

    teams.each do |team|
      break unless @account.within_email_rate_limit?

      TeamNotifications::AutomationNotificationMailer.conversation_creation(@conversation, team, params[0][:message])&.deliver_now
      @account.increment_email_sent_count
    end
  end
end
