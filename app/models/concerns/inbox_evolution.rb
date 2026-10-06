module InboxEvolution
  extend ActiveSupport::Concern

  included do
    validate :ensure_evolution_name, if: :will_save_change_to_name?
    after_destroy_commit :delete_evolution_instance
  end

  def evolution?
    channel.is_a?(Channel::Api) && channel.additional_attributes['provider'] == 'evolution'
  end

  private

  def ensure_evolution_name
    if evolution? && persisted?
      errors.add(:name, I18n.t('evolution.name_locked'))
      return
    end

    matches = self.class.where(account_id: account_id, name: name).where.not(id: id)
    evolution_channels = Channel::Api.where(account_id: account_id).where("additional_attributes->>'provider' = 'evolution'")
    conflict = matches.exists?(channel_type: 'Channel::Api', channel_id: evolution_channels.select(:id))
    errors.add(:name, :taken) if conflict || (evolution? && matches.exists?)
  end

  def delete_evolution_instance
    Evolution::DeleteInstanceJob.perform_later(account_id, id) if evolution?
  end
end
