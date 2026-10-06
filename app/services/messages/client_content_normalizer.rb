# Expand display tabs before message text reaches React Native's iOS text layout.
# Stored messages and channel/webhook delivery retain the original content.
class Messages::ClientContentNormalizer
  TAB_SPACES = '    '.freeze

  def self.normalize(text)
    text&.gsub("\t", TAB_SPACES)
  end
end
