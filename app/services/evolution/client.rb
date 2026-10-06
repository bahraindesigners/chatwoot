class Evolution::Client
  class Error < StandardError; end
  class NotFound < Error; end

  def self.configured?
    ENV['EVOLUTION_API_URL'].present? && ENV['EVOLUTION_API_KEY'].present?
  end

  def initialize
    raise Error unless self.class.configured?

    @url = ENV.fetch('EVOLUTION_API_URL').chomp('/')
    @headers = { 'apikey' => ENV.fetch('EVOLUTION_API_KEY'), 'Content-Type' => 'application/json' }
  end

  def status(instance)
    request(:get, "/instance/connectionState/#{instance}").fetch('instance').fetch('state')
  rescue NotFound
    'unpaired'
  rescue KeyError
    raise Error
  end

  def pair(inbox, user)
    instance = instance_name(inbox)
    if status(instance) == 'unpaired'
      request(:post, '/instance/create', {
                instanceName: instance, integration: 'WHATSAPP-BAILEYS', qrcode: false,
                groupsIgnore: true, alwaysOnline: false, readMessages: false, readStatus: false, syncFullHistory: false
              })
    end
    request(:post, "/chatwoot/set/#{instance}", {
              enabled: true, accountId: inbox.account_id.to_s, url: ENV.fetch('FRONTEND_URL'),
              token: user.access_token.token, nameInbox: inbox.name, signMsg: false,
              reopenConversation: true, conversationPending: false, importContacts: false, importMessages: false, autoCreate: false
            })
    return { state: 'open', qr: nil } if status(instance) == 'open'

    data = request(:get, "/instance/connect/#{instance}")
    qr = data['base64']
    raise Error if qr.present? && !qr.start_with?('data:image/png;base64,')

    { state: 'connecting', qr: qr }
  end

  def instance_name(inbox)
    "cw-#{inbox.account_id}-inbox-#{inbox.id}"
  end

  def webhook_url(inbox)
    "#{@url}/chatwoot/webhook/#{instance_name(inbox)}"
  end

  def deliver_webhook(inbox, body, headers:, timeout:)
    response = HTTParty.post(webhook_url(inbox), body: body, headers: headers, timeout: timeout, follow_redirects: false)
    raise Error unless response.success?
  end

  def delete_instance(account_id, inbox_id)
    request(:delete, "/instance/delete/cw-#{account_id}-inbox-#{inbox_id}")
  rescue NotFound
    nil
  end

  private

  def request(method, path, body = nil)
    options = { headers: @headers, timeout: 15 }
    options[:body] = body.to_json if body
    response = HTTParty.public_send(method, "#{@url}#{path}", **options)
    raise NotFound if response.code == 404
    raise Error unless response.success?

    JSON.parse(response.body)
  rescue JSON::ParserError, IOError, SystemCallError, SocketError, Timeout::Error, HTTParty::Error
    # Provider responses can contain tokens. Never forward their body/message to clients or logs.
    raise Error
  end
end
