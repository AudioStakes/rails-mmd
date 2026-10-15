# frozen_string_literal: true

require 'rails_mmd/schema_validator'

RSpec.describe RailsMmd::SchemaValidator do
  subject(:validator) { described_class.new }

  shared_examples 'unique attribute identities' do |schema_name, fixture_path|
    let(:payload) do
      JSON.parse(Pathname(__dir__).join('../../fixtures/schemas', fixture_path).read)
    end

    let(:duplicate_payload) do
      payload.tap do |document|
        attributes = document.fetch('entities').first.fetch('attributes')
        attributes << attributes.first.merge('type' => 'string')
      end
    end

    it 'accepts a valid document with distinct attribute identities' do
      expect(validator.valid?(schema_name, payload)).to be(true)
    end

    it 'rejects the same identity with different attribute content' do
      expect(validator.valid?(schema_name, duplicate_payload)).to be(false)
    end

    it 'reports the duplicate identity at its document path' do
      expect(validator.errors(schema_name, duplicate_payload)).to include(
        include('type' => 'unique_attribute_identity', 'data_pointer' => '/entities/0/attributes/2/attribute_id')
      )
    end

    it 'rejects duplicate identities at the publication validation boundary' do
      expect { validator.validate!(schema_name, duplicate_payload) }.to raise_error(described_class::InvalidPayload)
    end

    it 'rejects identities repeated across different entity payloads' do
      attribute_id = payload.fetch('entities').first.fetch('attributes').first.fetch('attribute_id')
      payload.fetch('entities').last.fetch('attributes').first['attribute_id'] = attribute_id

      expect(validator.valid?(schema_name, payload)).to be(false)
    end

    it 'still reports schema errors for malformed document and attribute shapes' do
      invalid_entities = [nil, 'invalid', [nil], [{ 'attributes' => nil }],
                          [{ 'attributes' => 'invalid' }], [{ 'attributes' => [nil, 1, 'invalid', {}] }]]
      documents = [nil, [], 'invalid'] + invalid_entities.map { |entities| payload.merge('entities' => entities) }

      documents.each { |document| expect(validator.errors(schema_name, document)).not_to be_empty }
    end
  end

  context 'with an IR document' do
    it_behaves_like 'unique attribute identities', :ir, 'ir/valid/core.json'
  end

  context 'with an ER render plan' do
    it_behaves_like 'unique attribute identities', :render_plan, 'render_plan/valid/er.json'
  end

  context 'with a class render plan' do
    before { payload['artifact_kind'] = 'class' }

    it_behaves_like 'unique attribute identities', :render_plan, 'render_plan/valid/er.json'
  end
end
