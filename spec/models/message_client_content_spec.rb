require 'rails_helper'

RSpec.describe Message do
  describe '#push_event_data' do
    subject(:push_event_data) { message.push_event_data }

    context 'with tabs in stored message content' do
      let(:message) do
        create(:message, content: "مرحبا\tworld", content_attributes: { email: { text_content: { quoted: "processed\ttext" } } })
      end

      it 'normalizes both client fields without rewriting the stored message' do
        expect(push_event_data).to include(content: 'مرحبا    world', processed_message_content: 'processed    text')
        expect(message.reload).to have_attributes(content: "مرحبا\tworld", processed_message_content: "processed\ttext")
      end

      it 'preserves canonical tabs in webhook payloads and outgoing delivery' do
        expect(message.webhook_push_event_data).to include(content: "مرحبا\tworld", processed_message_content: "processed\ttext")
        expect(message.webhook_data[:content]).to eq("مرحبا\tworld")
        expect(message.outgoing_content).to include("مرحبا\tworld")
      end
    end
  end
end
