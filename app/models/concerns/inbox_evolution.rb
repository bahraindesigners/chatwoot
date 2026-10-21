module InboxEvolution
  extend ActiveSupport::Concern

  included do
    validate :ensure_evolution_name, if: :will_save_change_to_name?
    after_destroy_commit :delete_evolution_instance
  end

  def evolution?
    channel.is_a?(Channel::Api) && channel.additional_attributes['provider'] == 'evolution'
  end

  def evolution_authorized?(configuration)
    expected = [true, ENV.fetch('FRONTEND_URL'), account_id.to_s, name]
    return false unless configuration.values_at('enabled', 'url', 'accountId', 'nameInbox') == expected

    owner = AccessToken.find_by(token: configuration['token'])&.owner
    evolution_user_authorized?(owner)
  end

  private

  def evolution_user_authorized?(owner)
    return false unless owner.is_a?(User)

    account_user = owner.account_users.find_by(account_id: account_id)
    return false unless account_user
    return false unless account_user.administrator? || owner.inboxes.exists?(id: id)

    account.api_and_webhooks_enabled? && evolution_mfa_authorized?(owner)
  end

  def evolution_mfa_authorized?(owner)
    !account.enforce_mfa? || owner.mfa_enabled? || owner.provider == 'saml'
  end

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
