# Focused dependency-free checks. These do not replace Rails integration tests.
# These minimal doubles are co-located because this script deliberately avoids Rails.
# rubocop:disable Style/OneClassPerFile
require 'erb'
require 'uri'
require 'yaml'

class Array
  def exclude?(value)
    !include?(value) # rubocop:disable Rails/NegateInclude
  end
end

class String
  def present?
    !strip.empty?
  end
end

class NilClass
  def present?
    false
  end
end

module GlobalConfig
  class << self
    attr_accessor :resolved

    def get(*keys)
      raise 'Unexpected branding configuration keys' unless keys == %w[BRAND_NAME BRAND_URL LOGO]

      resolved.dup
    end
  end
end

module ChatwootApp
  def self.chatwoot_cloud?
    false
  end
end

def assert(value, description)
  raise description unless value

  puts "PASS: #{description}"
end

source = File.read('app/mailers/application_mailer.rb')
method = source.split('  def self.branding_config', 2).last.split('  rescue_from', 2).first
mailer = Class.new
# Extracts the actual branding_config and its private URI helpers for isolated verification.
# rubocop:disable Style/DocumentDynamicEvalDefinition
mailer.class_eval("def self.branding_config#{method}", __FILE__, __LINE__)
# rubocop:enable Style/DocumentDynamicEvalDefinition
original_frontend_url = ENV.fetch('FRONTEND_URL', nil)
begin
  ENV['FRONTEND_URL'] = 'https://support.example.com/'
  GlobalConfig.resolved = { 'BRAND_NAME' => 'Lamma', 'LOGO' => '/brand-assets/lamma/logo.png' }
  assert(
    mailer.branding_config['LOGO_URL'] == 'https://support.example.com/brand-assets/lamma/logo.png', 'relative logo resolves to deployment origin'
  )
  GlobalConfig.resolved['LOGO'] = 'https://assets.example.com/logo.png'
  assert(mailer.branding_config['LOGO_URL'] == GlobalConfig.resolved['LOGO'], 'absolute logo destination remains unchanged')
  ENV.delete('FRONTEND_URL')
  assert(mailer.branding_config['LOGO_URL'] == GlobalConfig.resolved['LOGO'], 'valid absolute logo does not need deployment URL')
  ENV['FRONTEND_URL'] = 'https://support.example.com'
  ['http://[', 'javascript:alert(1)', 'ftp://assets.example.com/logo.png', 'https://user:password@assets.example.com/logo.png',
   '//assets.example.com/logo.png', 'brand-assets/logo.png', '/brand-assets/../logo.png', false].each do |logo|
    GlobalConfig.resolved['LOGO'] = logo
    assert(!mailer.branding_config.key?('LOGO_URL'), "unsafe or malformed logo omitted: #{logo.inspect}")
  end
  GlobalConfig.resolved['LOGO'] = '/brand-assets/lamma/logo.png'
  ['http://[', 'javascript:alert(1)', '//support.example.com', 'https://user:password@support.example.com'].each do |url|
    ENV['FRONTEND_URL'] = url
    assert(!mailer.branding_config.key?('LOGO_URL'), "unsafe or malformed deployment URL omitted: #{url.inspect}")
  end
  ENV['FRONTEND_URL'] = 'https://support.example.com'
  GlobalConfig.resolved['LOGO'] = nil
  assert(!mailer.branding_config.key?('LOGO_URL'), 'missing resolved logo omits email logo')
  ENV.delete('FRONTEND_URL')
  assert(!mailer.branding_config.key?('LOGO_URL'), 'missing deployment URL omits email logo')
  ENV['FRONTEND_URL'] = 'https://support.example.com'
  GlobalConfig.resolved = { 'BRAND_NAME' => 'Chatwoot', 'LOGO' => '/brand-assets/logo.svg' }
  assert(mailer.branding_config['BRAND_NAME'] == 'Chatwoot', 'resolved community name remains upstream')
  assert(mailer.branding_config['LOGO_URL'].end_with?('/brand-assets/logo.svg'), 'resolved community logo remains upstream')
ensure
  original_frontend_url.nil? ? ENV.delete('FRONTEND_URL') : ENV['FRONTEND_URL'] = original_frontend_url
end

template = File.read('app/views/layouts/vueapp.html.erb').split('<%= csrf_meta_tags %>').first
@global_config = { 'INSTALLATION_NAME' => 'Lamma', 'DISPLAY_MANIFEST' => true, 'LOGO_THUMBNAIL' => '/brand-assets/lamma/logo-thumbnail.png' }
rendered = ERB.new(template).result(binding)
assert(rendered.include?('<title>') && rendered.include?('Lamma'), 'page title uses resolved installation name')
# Plain Ruby does not provide Active Support's exclude? in this isolated harness.
# rubocop:disable Rails/NegateInclude
assert(
  !rendered.include?('/favicon-32x32.png') && !rendered.include?('/manifest.json'),
  'custom thumbnail avoids upstream favicon and manifest overrides'
)
# rubocop:enable Rails/NegateInclude
assert(rendered.include?('rel="apple-touch-icon" href="/brand-assets/lamma/logo-thumbnail.png"'), 'custom thumbnail supplies touch icon')
@global_config['LOGO_THUMBNAIL'] = '/brand-assets/logo_thumbnail.svg'
rendered = ERB.new(template).result(binding)
assert(rendered.include?('/manifest.json') && rendered.include?('/favicon-32x32.png'), 'default installation retains upstream manifest and favicons')
@global_config['DISPLAY_MANIFEST'] = false
@global_config['LOGO_THUMBNAIL'] = '/brand-assets/lamma/logo-thumbnail.png'
rendered = ERB.new(template).result(binding)
assert(rendered.include?('rel="icon" href="/brand-assets/lamma/logo-thumbnail.png"'), 'configured favicon remains when metadata disabled')

profile = YAML.safe_load(File.read('docs/branding/lamma.yml'))
assert(
  profile.keys.sort == %w[INSTALLATION_NAME BRAND_NAME LOGO LOGO_DARK LOGO_THUMBNAIL].sort,
  'review profile excludes unknown legal and external destinations'
)
assert(profile.values.grep(%r{^/brand-assets/}).all? { |path| File.file?("public#{path}") }, 'every configured logo exists in the reusable image')

# rubocop:enable Style/OneClassPerFile
