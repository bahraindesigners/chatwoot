require 'rails_helper'

RSpec.describe ApplicationMailer do
  describe '.branding_config' do
    let(:config) { { 'BRAND_NAME' => 'Lamma', 'BRAND_URL' => 'https://example.com', 'LOGO' => '/brand-assets/lamma/logo.png' } }

    before do
      allow(GlobalConfig).to receive(:get).with('BRAND_NAME', 'BRAND_URL', 'LOGO') { config.dup }
    end

    it 'uses resolved installation configuration for the absolute email logo' do
      with_modified_env FRONTEND_URL: 'https://support.example.com/' do
        expect(described_class.branding_config).to include(config.merge('LOGO_URL' => 'https://support.example.com/brand-assets/lamma/logo.png'))
      end
    end

    it 'preserves an absolute logo destination' do
      config['LOGO'] = 'https://assets.example.com/logo.png'
      with_modified_env FRONTEND_URL: 'https://support.example.com' do
        expect(described_class.branding_config['LOGO_URL']).to eq(config['LOGO'])
      end
    end

    it 'does not add a logo URL without a deployment URL' do
      with_modified_env FRONTEND_URL: nil do
        expect(described_class.branding_config).not_to have_key('LOGO_URL')
      end
    end

    it 'does not add a logo URL without a resolved logo' do
      config['LOGO'] = nil
      with_modified_env FRONTEND_URL: 'https://support.example.com' do
        expect(described_class.branding_config).not_to have_key('LOGO_URL')
      end
    end

    it 'omits malformed or unsafe configured logos without blocking email' do
      with_modified_env FRONTEND_URL: 'https://support.example.com' do
        ['http://[', 'javascript:alert(1)', '//assets.example.com/logo.png', '/brand-assets/../logo.png', false].each do |logo|
          config['LOGO'] = logo
          expect(described_class.branding_config).not_to have_key('LOGO_URL')
        end
      end
    end

    it 'omits relative logos when the deployment URL is malformed or unsafe' do
      ['http://[', 'javascript:alert(1)', '//support.example.com'].each do |url|
        with_modified_env FRONTEND_URL: url do
          expect(described_class.branding_config).not_to have_key('LOGO_URL')
        end
      end
    end

    it 'uses a valid absolute logo without needing the deployment URL' do
      config['LOGO'] = 'https://assets.example.com/logo.png'
      with_modified_env FRONTEND_URL: nil do
        expect(described_class.branding_config['LOGO_URL']).to eq(config['LOGO'])
      end
    end

    it 'respects the upstream name and logo after plan reconciliation' do
      config['BRAND_NAME'] = 'Chatwoot'
      config['LOGO'] = '/brand-assets/logo.svg'
      with_modified_env FRONTEND_URL: 'https://support.example.com' do
        expect(described_class.branding_config).to include(
          'BRAND_NAME' => 'Chatwoot', 'LOGO_URL' => 'https://support.example.com/brand-assets/logo.svg'
        )
      end
    end
  end
end
