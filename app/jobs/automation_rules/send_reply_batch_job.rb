class AutomationRules::SendReplyBatchJob < ApplicationJob
  queue_as :high

  def perform(message_ids)
    message_ids.each { |message_id| SendReplyJob.perform_now(message_id) }
  end
end
