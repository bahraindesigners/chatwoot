require 'rails_helper'

RSpec.describe Messages::ClientContentNormalizer do
  describe '.normalize' do
    it 'preserves nil attachment-only content' do
      expect(described_class.normalize(nil)).to be_nil
    end

    it 'preserves text without tabs' do
      expect(described_class.normalize("مرحبا\nworld  ")).to eq("مرحبا\nworld  ")
    end

    it 'expands consecutive tabs while preserving Arabic text and line breaks' do
      expect(described_class.normalize("مرحبا\t\tworld\nnext")).to eq("مرحبا        world\nnext")
    end

    it 'does not mutate the original frozen message' do
      source = "مرحبا\tworld".freeze
      expect(described_class.normalize(source)).to eq('مرحبا    world')
      expect(source).to eq("مرحبا\tworld")
    end
  end
end
