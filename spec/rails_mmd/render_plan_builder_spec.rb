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

  it 'redacts broad secret assignments from comments before schema validation' do
    result = described_class.new.build(
      ir: ir_payload,
      artifact_kind: 'er',
      direction: 'LR',
      comments: [
        { 'comment_id' => 'comments/secrets',
          'text' => 'client_secret=foo credential=abc123 database_url=postgres://u:p@db refresh_token:def456' }
      ]
    )
    comment_text = result.payload.fetch('comments').first.fetch('text')

    expect(comment_text).not_to include('foo', 'abc123', 'postgres://u:p@db', 'def456')
    expect(schema_valid_render_plan?(result.payload)).to be(true)
  end

  it 'normalizes Mermaid-facing comments to sanitized single-line text before schema validation' do
    result = described_class.new.build(
      ir: ir_payload,
      artifact_kind: 'er',
      direction: 'LR',
      comments: [
        { 'comment_id' => 'comments/control', 'text' => "first\nsecond\tthird\u0007 /tmp/project token=secret" }
      ]
    )
    text = result.payload.fetch('comments').first.fetch('text')

    expect(text).to eq('first second third [REDACTED_PATH] [REDACTED]')
    expect(text).not_to match(/[\r\n\t[:cntrl:]]/)
    expect(schema_valid_render_plan?(result.payload)).to be(true)
  end

  it 'redacts secret assignments and paths split by control characters' do
    result = described_class.new.build(
      ir: ir_payload,
      artifact_kind: 'er',
      direction: 'LR',
      comments: [
        { 'comment_id' => 'comments/split_secret',
          'text' => "api\n_key=supersecret /tmp/pri\nvate/token=hidden" }
      ]
    )
    text = result.payload.fetch('comments').first.fetch('text')

    expect(text).to eq('[REDACTED] [REDACTED_PATH]')
    expect(text).not_to include('supersecret', 'hidden', 'pri', 'vate')
    expect(schema_valid_render_plan?(result.payload)).to be(true)
  end

  it 'redacts generic absolute paths split by control characters in free text' do
    result = described_class.new.build(
      ir: ir_payload,
      artifact_kind: 'er',
      direction: 'LR',
      comments: [
        { 'comment_id' => 'comments/generic_split_path', 'text' => "/etc/pa\nsswd token=abc" }
      ]
    )
    text = result.payload.fetch('comments').first.fetch('text')

    expect(text).to eq('[REDACTED_PATH] [REDACTED]')
    expect(text).not_to include('etc', 'pa', 'sswd', 'abc')
    expect(schema_valid_render_plan?(result.payload)).to be(true)
  end

  it 'redacts punctuation-adjacent absolute paths split by control characters in free text' do
    result = described_class.new.build(
      ir: ir_payload,
      artifact_kind: 'er',
      direction: 'LR',
      comments: [
        { 'comment_id' => 'comments/punctuation_split_path', 'text' => "prefix(/etc/pa\nsswd) token=abc" }
      ]
    )
    text = result.payload.fetch('comments').first.fetch('text')

    expect(text).to eq('prefix([REDACTED_PATH]) [REDACTED]')
    expect(text).not_to include('etc', 'pa', 'sswd', 'abc')
    expect(schema_valid_render_plan?(result.payload)).to be(true)
  end

  it 'does not redact relative paths or URLs as absolute paths in free text' do
    result = described_class.new.build(
      ir: ir_payload,
      artifact_kind: 'er',
      direction: 'LR',
      comments: [
        { 'comment_id' => 'comments/benign_slashes',
          'text' => 'see foo/bar and https://example.com/x?token=abc plus postgres://user:pass@example.com/db' }
      ]
    )
    text = result.payload.fetch('comments').first.fetch('text')

    expect(text).to eq('see foo/bar and [REDACTED_URL] plus [REDACTED_URL]')
    expect(schema_valid_render_plan?(result.payload)).to be(true)
  end

  it 'does not restore literal URL placeholders or redact standalone slashes' do
    result = described_class.new.build(
      ir: ir_payload,
      artifact_kind: 'er',
      direction: 'LR',
      comments: [
        { 'comment_id' => 'comments/url_placeholder', 'text' => 'literal RAILSMMDURL0 / and https://example.com/x' }
      ]
    )
    text = result.payload.fetch('comments').first.fetch('text')

    expect(text).to eq('literal RAILSMMDURL0 / and [REDACTED_URL]')
    expect(schema_valid_render_plan?(result.payload)).to be(true)
  end

  it 'does not free-text redact credential-looking structured column labels or token sources' do
    ir = ir_payload
    user_attributes = ir.fetch('entities').first.fetch('attributes')
    user_attributes[0]['name'] = 'api_key'
    user_attributes[1]['name'] = 'password_digest'

    result = described_class.new.build(ir: ir, artifact_kind: 'er', direction: 'LR')
    labels = user_attribute_payloads(result.payload).map { |attribute| attribute.fetch('label') }
    tokens = user_attribute_payloads(result.payload).map { |attribute| attribute.fetch('safe_token') }

    expect(labels).to eq(%w[api_key password_digest])
    expect(tokens).to include('API_KEY', 'PASSWORD_DIGEST')
    expect(tokens).not_to include('REDACTED_KEY')
    expect(schema_valid_render_plan?(result.payload)).to be(true)
  end

  it 'does not free-text redact credential-looking structured entity labels or token sources' do
    ir = ir_payload
    ir.fetch('entities').first['ruby_constant'] = 'ApiKey'

    result = described_class.new.build(ir: ir, artifact_kind: 'er', direction: 'LR')
    entity = result.payload.fetch('entities').find { |candidate| candidate.fetch('entity_id') == 'entities/users' }

    expect(entity.fetch('label')).to eq('ApiKey')
    expect(entity.fetch('safe_token')).to eq('API_KEY')
    expect(schema_valid_render_plan?(result.payload)).to be(true)
  end

  it 'does not free-text redact credential-looking structured relationship labels or token sources' do
    ir = ir_payload
    ir.fetch('relationships').first['association_name'] = 'access_token'

    result = described_class.new.build(ir: ir, artifact_kind: 'er', direction: 'LR')
    relationship = result.payload.fetch('relationships').first

    expect(relationship.fetch('label')).to eq('access_token')
    expect(relationship.fetch('safe_token')).to eq('ACCESS_TOKEN')
    expect(schema_valid_render_plan?(result.payload)).to be(true)
  end

  it 'strips accepted association label suffixes before relationship labels and token sources' do
    ['?', '!', '='].each do |suffix|
      ir = ir_payload
      ir.fetch('relationships').first['association_name'] = "account#{suffix}"

      result = described_class.new.build(ir: ir, artifact_kind: 'er', direction: 'LR')
      relationship = result.payload.fetch('relationships').first

      expect(relationship.fetch('label')).to eq('account')
      expect(relationship.fetch('safe_token')).to eq('ACCOUNT')
      expect(schema_valid_render_plan?(result.payload)).to be(true)
    end
  end

  it 'sanitizes unsafe attribute names before labels and safe-token assignment' do
    ir = ir_payload
    ir.fetch('entities').first.fetch('attributes').first['name'] = '/Users/alice/.ssh/id_rsa token=abc123'

    result = described_class.new.build(ir: ir, artifact_kind: 'er', direction: 'LR')
    attribute = result.payload.fetch('entities').find { |entity| entity.fetch('entity_id') == 'entities/users' }
                                                .fetch('attributes')
                                                .find { |candidate| candidate.fetch('key_marker') == 'PK' }

    expect(attribute.fetch('label')).to eq('X')
    expect(attribute.fetch('safe_token')).not_to include('USERS', 'ALICE', 'ABC123')
    expect(schema_valid_render_plan?(result.payload)).to be(true)
  end

  it 'normalizes attribute labels and relationship labels without leaking unsafe token sources' do
    ir = ir_payload
    ir.fetch('entities').first.fetch('attributes').first['name'] = "id\n/tmp/project\tsecret=abc"
    ir.fetch('relationships').first['association_name'] = "account\n/tmp/project\tsecret=abc"

    result = described_class.new.build(ir: ir, artifact_kind: 'er', direction: 'LR')
    attribute = result.payload.fetch('entities').find { |entity| entity.fetch('entity_id') == 'entities/users' }
                                                .fetch('attributes')
                                                .find { |candidate| candidate.fetch('key_marker') == 'PK' }
    relationship = result.payload.fetch('relationships').first

    expect(attribute.fetch('label')).to eq('X')
    expect(attribute.fetch('safe_token')).not_to include('TMP', 'PROJECT', 'ABC')
    expect(relationship.fetch('label')).to eq('X')
    expect(relationship.fetch('safe_token')).not_to include('TMP', 'PROJECT', 'ABC')
    expect(schema_valid_render_plan?(result.payload)).to be(true)
  end

  it 'falls back for malformed structured labels and token sources' do
    ir = ir_payload
    ir.fetch('entities').first['ruby_constant'] = '/etc/passwd'
    ir.fetch('entities').first.fetch('attributes').first['name'] = 'foo/bar'
    ir.fetch('relationships').first['association_name'] = 'core.api'

    result = described_class.new.build(ir: ir, artifact_kind: 'er', direction: 'LR')
    entity = result.payload.fetch('entities').find { |candidate| candidate.fetch('entity_id') == 'entities/users' }
    attribute = entity.fetch('attributes').find { |candidate| candidate.fetch('key_marker') == 'PK' }
    relationship = result.payload.fetch('relationships').first

    expect(entity.fetch('label')).to eq('X')
    expect(entity.fetch('safe_token')).to eq('X')
    expect(attribute.fetch('label')).to eq('X')
    expect(attribute.fetch('safe_token')).to eq('X')
    expect(relationship.fetch('label')).to eq('X')
    expect(relationship.fetch('safe_token')).to eq('X')
    expect(schema_valid_render_plan?(result.payload)).to be(true)
  end

  it 'normalizes entity labels without leaking unsafe label sources into safe tokens' do
    ir = ir_payload
    ir.fetch('entities').first['ruby_constant'] = "User\n/tmp/project\tsecret=abc"

    result = described_class.new.build(ir: ir, artifact_kind: 'er', direction: 'LR')
    entity = result.payload.fetch('entities').find { |candidate| candidate.fetch('entity_id') == 'entities/users' }

    expect(entity.fetch('label')).to eq('X')
    expect(entity.fetch('safe_token')).not_to include('TMP', 'PROJECT', 'ABC')
    expect(schema_valid_render_plan?(result.payload)).to be(true)
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

  def user_attribute_payloads(payload)
    payload.fetch('entities').find { |entity| entity.fetch('entity_id') == 'entities/users' }.fetch('attributes')
  end

  def schema_valid_render_plan?(payload)
    RailsMmd::SchemaValidator.new.valid?(:render_plan, payload)
  end
end
# rubocop:enable Metrics/MethodLength, RSpec/ExampleLength, RSpec/MultipleExpectations
