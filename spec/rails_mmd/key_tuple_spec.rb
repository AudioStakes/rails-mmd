# frozen_string_literal: true

require 'rails_mmd/key_tuple'

# rubocop:disable RSpec/ExampleLength, RSpec/MultipleExpectations
RSpec.describe RailsMmd::KeyTuple do
  describe '.normalize' do
    it 'normalizes a scalar column into a frozen tuple' do
      expect(described_class.normalize('id')).to eq(['id'])
      expect(described_class.normalize('id')).to be_frozen
    end

    it 'preserves array order in an immutable copy' do
      source = %w[store_id sku]
      normalized = described_class.normalize(source)
      source.reverse!

      expect(normalized).to eq(%w[store_id sku])
      expect(normalized).to be_frozen
      expect(normalized).to all(be_frozen)
    end

    it 'rejects empty, duplicate, nested, and non-string tuple shapes' do
      invalid_values = [nil, '', [], [''], %w[id id], [['id']], [:id], ['id', :tenant_id]]

      expect(invalid_values.map { |value| described_class.normalize(value) }).to all(be_nil)
    end
  end

  describe '.valid_pair?' do
    it 'accepts equally sized valid tuples and rejects incomplete or unequal pairs' do
      expect(described_class.valid_pair?(%w[shop_id basket_id], %w[shop_id id])).to be(true)
      expect(described_class.valid_pair?('account_id', 'id')).to be(true)
      expect(described_class.valid_pair?(%w[shop_id basket_id], ['id'])).to be(false)
      expect(described_class.valid_pair?([], [])).to be(false)
      expect(described_class.valid_pair?(['id', :tenant_id], %w[tenant_id id])).to be(false)
    end
  end

  describe '.identity' do
    it 'serializes structured tuple payloads as canonical JSON' do
      payload = { referenced_key_columns: %w[shop_id id], kind: 'direct', foreign_key_columns: %w[shop_id basket_id] }

      expect(described_class.identity(payload)).to eq(
        '{"foreign_key_columns":["shop_id","basket_id"],"kind":"direct",' \
        '"referenced_key_columns":["shop_id","id"]}'
      )
    end
  end
end
# rubocop:enable RSpec/ExampleLength, RSpec/MultipleExpectations
