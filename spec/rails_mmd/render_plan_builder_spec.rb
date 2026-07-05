# frozen_string_literal: true

require 'rails_mmd/canonical_json'
require 'rails_mmd/ir_builder'
require 'rails_mmd/render_plan_builder'
require 'rails_mmd/schema_probe'
require 'rails_mmd/schema_validator'

# rubocop:disable Metrics/MethodLength, RSpec/ExampleLength, RSpec/MultipleExpectations
RSpec.describe RailsMmd::RenderPlanBuilder do
  it 'projects IR into schema-valid ER render plans with safe tokens, markers, attributes, comments, and digest' do
    result = described_class.new.build(
      ir: ir_payload,
      artifact_kind: 'er',
      direction: 'LR',
      attributes: :keys,
      comments: [
        { 'comment_id' => 'comments/unsafe',
          'text' => '/tmp/project token=secret123 password hunter2 api_key abc123 pid=1234' }
      ],
      available_diagnostic_ids: %w[d_db_metadata_degraded]
    )
    payload = result.payload

    expect(payload.fetch('entities').map { |entity| entity.fetch('safe_token') }).to eq(%w[ACCOUNT USER])
    expect(payload.fetch('entities').flat_map { |entity| entity.fetch('attributes') }.map do |attribute|
      attribute.fetch('safe_token')
    end).to include('ID_H4D273AD96F8C', 'ID_H704E47D169CA')
    expect(payload.fetch('entities').last.fetch('attributes').map { |attribute| attribute.fetch('type') }).to eq(
      %w[bigint unknown]
    )
    expect(payload.fetch('relationships').first).to include(
      'er_left_marker' => '}o',
      'er_right_marker' => '||',
      'class_owner_multiplicity' => '0..*',
      'class_target_multiplicity' => '1'
    )
    expect(payload.fetch('comments').first.fetch('text')).not_to include('/tmp', 'token=', 'pid=')
    expect(payload.fetch('comments').first.fetch('safe_token')).not_to include('TMP', 'SECRET123', 'PID')
    expect(payload.fetch('diagnostic_ids')).to eq(['d_db_metadata_degraded'])
    expect(schema_valid_render_plan?(payload)).to be(true)
    expect(payload.fetch('digest_sha256')).to eq(
      RailsMmd::CanonicalJson.digest_sha256(payload.merge('digest_sha256' => nil))
    )
  end

  it 'uses IR cardinalities directly for class plans and supports attributes none' do
    result = described_class.new.build(
      ir: ir_payload(owner_cardinality: '0..1', target_cardinality: '0..many'),
      artifact_kind: 'class',
      direction: 'BT',
      attributes: :none
    )
    relationship = result.payload.fetch('relationships').first

    expect(result.payload.fetch('entities').flat_map { |entity| entity.fetch('attributes') }).to eq([])
    expect(relationship.fetch('class_owner_multiplicity')).to eq('0..1')
    expect(relationship.fetch('class_target_multiplicity')).to eq('0..*')
    expect(relationship.fetch('er_left_marker')).to eq('|o')
    expect(relationship.fetch('er_right_marker')).to eq('o{')
    expect(schema_valid_render_plan?(result.payload)).to be(true)
  end

  it 'projects the full cardinality marker and multiplicity matrix' do
    expectations = {
      '0..1' => ['|o', 'o|', '0..1'],
      '1..1' => ['||', '||', '1'],
      '0..many' => ['}o', 'o{', '0..*'],
      '1..many' => ['}|', '|{', '1..*']
    }

    expectations.each do |cardinality, (left_marker, right_marker, multiplicity)|
      relationship = described_class.new.build(
        ir: ir_payload(owner_cardinality: cardinality, target_cardinality: cardinality),
        artifact_kind: 'er',
        direction: 'LR'
      ).payload.fetch('relationships').first

      expect(relationship).to include(
        'er_left_marker' => left_marker,
        'er_right_marker' => right_marker,
        'class_owner_multiplicity' => multiplicity,
        'class_target_multiplicity' => multiplicity
      )
    end
  end

  it 'propagates safe-token collision diagnostics and resolved tokens' do
    result = described_class.new.build(ir: ir_payload, artifact_kind: 'er', direction: 'LR')
    tokens = result.payload.fetch('entities').flat_map { |entity| entity.fetch('attributes') }.map do |attribute|
      attribute.fetch('safe_token')
    end

    expect(tokens).to include('ID_H4D273AD96F8C', 'ID_H704E47D169CA')
    expect(result.diagnostics.map { |diagnostic| diagnostic.fetch('code') }).to eq(['SAFE_TOKEN_COLLISION'])
  end

  it 'preserves probed IR attribute types through render-plan projection' do
    entity = RailsMmd::SchemaProbe::Entity.new(
      ruby_constant: 'User',
      table_name: 'users',
      connection_context_id: '{"name":"primary"}',
      columns: [RailsMmd::SchemaProbe::Column.new(name: 'id', type: :bigint, nullable: false)],
      primary_key: 'id',
      foreign_keys: [],
      indexes: []
    )
    ir = RailsMmd::IrBuilder.new.build(
      domains: [RailsMmd::SchemaProbe::DomainResult.new(domain_id: 'core', entities: [entity], diagnostics: [])],
      relationship_domains: []
    ).domains.first.payload

    render_plan = described_class.new.build(ir: ir, artifact_kind: 'er', direction: 'LR').payload

    expect(render_plan.fetch('entities').first.fetch('attributes').first.fetch('type')).to eq('bigint')
  end

  def ir_payload(owner_cardinality: '0..many', target_cardinality: '1..1')
    {
      'schema_version' => 1,
      'domain_id' => 'core',
      'entities' => [
        {
          'entity_id' => 'entities/users',
          'ruby_constant' => 'User',
          'table_name' => 'users',
          'attributes' => [
            { 'attribute_id' => 'entities/users/attributes/id', 'name' => 'id', 'role' => 'primary_key',
              'type' => 'BIGINT' },
            { 'attribute_id' => 'entities/users/attributes/account_id', 'name' => 'account_id',
              'role' => 'foreign_key', 'type' => 'ltree' }
          ]
        },
        {
          'entity_id' => 'entities/accounts',
          'ruby_constant' => 'Account',
          'table_name' => 'accounts',
          'attributes' => [
            { 'attribute_id' => 'entities/accounts/attributes/id', 'name' => 'id', 'role' => 'primary_key',
              'type' => 'bigint' }
          ]
        }
      ],
      'relationships' => [
        {
          'relationship_id' => 'relationships/users/account',
          'owner_entity_id' => 'entities/users',
          'target_entity_id' => 'entities/accounts',
          'association_name' => 'account',
          'owner_cardinality' => owner_cardinality,
          'target_cardinality' => target_cardinality
        }
      ],
      'diagnostic_ids' => %w[d_db_metadata_degraded d_missing],
      'digest_sha256' => 'b' * 64
    }
  end

  def schema_valid_render_plan?(payload)
    RailsMmd::SchemaValidator.new.valid?(:render_plan, payload)
  end
end
# rubocop:enable Metrics/MethodLength, RSpec/ExampleLength, RSpec/MultipleExpectations
