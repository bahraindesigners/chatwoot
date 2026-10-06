class Evolution::DeleteInstanceJob < ApplicationJob
  queue_as :low

  def perform(account_id, inbox_id)
    Evolution::Client.new.delete_instance(account_id, inbox_id)
  end
end
