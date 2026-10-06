class Api::V1::Accounts::EvolutionController < Api::V1::Accounts::BaseController
  before_action :authorize_administrator
  before_action :ensure_configured
  before_action :fetch_inbox, except: :create
  rescue_from Evolution::Client::Error, with: :render_provider_error

  def create
    name = params[:name]
    unless name.is_a?(String) && name.strip.present? && name.length <= 100
      render json: { message: I18n.t('evolution.invalid_name') }, status: :unprocessable_entity
      return
    end

    ActiveRecord::Base.transaction do
      channel = Current.account.api_channels.create!(additional_attributes: { provider: 'evolution' })
      @inbox = Current.account.inboxes.create!(name: name.strip, channel: channel)
      channel.update!(webhook_url: Evolution::Client.new.webhook_url(@inbox))
    end
    render partial: 'api/v1/models/inbox', locals: { resource: @inbox }, status: :created
  end

  def status
    client = Evolution::Client.new
    render json: { state: client.status(client.instance_name(@inbox)) }
  end

  def qr
    # Serialize provisioning for this inbox so simultaneous refreshes cannot create duplicate instances.
    @inbox.with_lock do
      render json: Evolution::Client.new.pair(@inbox, Current.user)
    end
  end

  private

  def authorize_administrator
    authorize Inbox, :create?
  end

  def ensure_configured
    return if Evolution::Client.configured?

    render json: { message: I18n.t('evolution.not_configured') }, status: :service_unavailable
  end

  def fetch_inbox
    @inbox = Current.account.inboxes.find(params[:inbox_id])
    authorize @inbox, :update?
    raise ActiveRecord::RecordNotFound unless @inbox.api? && @inbox.channel.additional_attributes['provider'] == 'evolution'
  end

  def render_provider_error
    render json: { message: I18n.t('evolution.provider_error') }, status: :bad_gateway
  end
end
