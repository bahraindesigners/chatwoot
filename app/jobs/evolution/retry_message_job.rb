class Evolution::RetryMessageJob < ApplicationJob
  queue_as :high

  def perform(message_id)
    message = Message.find(message_id)
    channel = message.inbox.channel
    WebhookJob.perform_now(channel.webhook_url, message.webhook_data.merge(event: 'message_created'), :api_inbox_webhook,
                           secret: channel.secret, delivery_id: SecureRandom.uuid)
  end
end
