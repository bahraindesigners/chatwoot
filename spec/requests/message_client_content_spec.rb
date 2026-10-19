require 'rails_helper'

RSpec.describe 'Client message content', type: :request do
  let(:account) { create(:account) }
  let(:agent) { create(:user, account: account, role: :agent) }
  let(:conversation) { create(:conversation, account: account) }
  let!(:message) { create(:message, conversation: conversation, account: account, content: "مرحبا\tworld") }

  before do
    create(:inbox_member, inbox: conversation.inbox, user: agent)
  end

  it 'expands tabs in message history without changing stored text' do
    get "/api/v1/accounts/#{account.id}/conversations/#{conversation.display_id}/messages",
        headers: agent.create_new_auth_token,
        as: :json

    expect(response).to have_http_status(:success)
    expect(response.parsed_body['payload'].find { |item| item['id'] == message.id }['content']).to eq('مرحبا    world')
    expect(message.reload.content).to eq("مرحبا\tworld")
  end

  it 'expands tabs in conversation search previews without changing stored text' do
    get "/api/v1/accounts/#{account.id}/conversations/search",
        headers: agent.create_new_auth_token,
        params: { q: 'world' },
        as: :json

    expect(response).to have_http_status(:success)
    expect(response.parsed_body['payload'].first['messages'].first['content']).to eq('مرحبا    world')
    expect(message.reload.content).to eq("مرحبا\tworld")
  end
end
