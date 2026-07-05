# frozen_string_literal: true

require 'rails_mmd/canonical_json'
require 'rails_mmd/diagnostics'
require 'rails_mmd/ordering'
require 'rails_mmd/redactor'
require 'rails_mmd/safe_tokens'
require 'rails_mmd/schema_validator'

# rubocop:disable RSpec/DescribeClass, RSpec/ExampleLength, RSpec/MultipleExpectations
RSpec.describe 'runtime primitives' do
  describe RailsMmd::CanonicalJson do
    it 'canonicalizes object keys and computes lowercase SHA-256 digests' do
      payload = { 'b' => 2, 'a' => { 'd' => 4, 'c' => 3 } }

      expect(described_class.dump(payload)).to eq('{"a":{"c":3,"d":4},"b":2}')
      expect(described_class.digest_sha256(payload)).to match(/\A[0-9a-f]{64}\z/)
    end
  end

  describe RailsMmd::Redactor do
    it 'sanitizes paths, URL credentials, environment values, and credential-looking text' do
      redactor = described_class.new(project_root: Dir.pwd, env: { 'SECRET' => 'super-secret-value' })
      text = "#{Dir.pwd}/config/rails_mmd.yml /tmp/outside.yml " \
             'postgres://user:pass@example/db super-secret-value api_key'

      expect(redactor.sanitize(text)).to include('config/rails_mmd.yml')
      expect(redactor.sanitize(text)).not_to include(Dir.pwd, '/tmp/outside.yml', 'user:pass', 'super-secret-value',
                                                     'api_key')
      expect(redactor.sanitize_object(['super-secret-value'])).to eq(['[REDACTED]'])
      expect(redactor.sanitize_object('api_key' => 'super-secret-value')).to eq('[REDACTED_KEY]' => '[REDACTED]')
      expect(redactor.sanitize_object(42)).to eq(42)
    end
  end

  describe RailsMmd::SchemaValidator do
    it 'validates repository schema payloads through json_schemer' do
      validator = described_class.new

      expect(validator.valid?(:diagnostics, fixture('diagnostics/valid/catalog.json'))).to be(true)
      expect(validator.valid?(:diagnostics, fixture('diagnostics/invalid/unknown_code.json'))).to be(false)
      expect(validator.errors(:diagnostics, fixture('diagnostics/invalid/unknown_code.json'))).not_to be_empty
    end
  end

  describe RailsMmd::Diagnostics do
    it 'exposes the closed diagnostic catalog from the schema fixture' do
      expect(described_class.codes).to include('CONFIG_NOT_FOUND', 'SAFE_TOKEN_COLLISION', 'INTERNAL_ERROR')
      expect(described_class.codes).not_to include('UNKNOWN_CODE')
    end

    it 'builds schema-valid closed diagnostics and rejects extra metadata' do
      diagnostic = described_class.new.build(
        code: 'CONFIG_NOT_FOUND',
        subject_id: 'config',
        message: "Missing #{Dir.pwd}/rails_mmd.yml",
        metadata: { config_path: "#{Dir.pwd}/rails_mmd.yml" }
      )

      expect(RailsMmd::SchemaValidator.new.valid?(:diagnostics, diagnostics_document([diagnostic]))).to be(true)
      expect(diagnostic.fetch('artifact_refs')).to eq([])
      expect(diagnostic.fetch('message')).not_to include(Dir.pwd)
      expect(structured_identifier_metadata.fetch('ruby_constant')).to eq('Credential::ApiKey')
      expect do
        described_class.new.build(
          code: 'CONFIG_NOT_FOUND',
          message: 'missing',
          metadata: { config_path: 'rails_mmd.yml', extra: true }
        )
      end.to raise_error(ArgumentError, /unknown diagnostic metadata/)
      expect do
        described_class.new.build(code: 'CONFIG_NOT_FOUND', message: 'missing', metadata: {})
      end.to raise_error(ArgumentError, /missing diagnostic metadata/)
    end

    it 'normalizes diagnostic ids after redaction and validates artifact refs' do
      diagnostics = described_class.new

      expect(machine_local_config_id).to eq(relative_config_id)
      expect(structured_subject_id).to eq('core:Credential::ApiKey:password_digest')
      expect(free_text_array_metadata).to eq(['log.txt', 12])
      expect do
        diagnostics.build(
          code: 'SAFE_TOKEN_COLLISION',
          message: 'collision',
          metadata: safe_token_metadata(token_kind: 'entity'),
          artifact_refs: [{ artifact_kind: 'stderr', domain_id: nil, path: '/tmp/rails-mmd/stderr.log' }]
        )
      end.to raise_error(ArgumentError, /invalid artifact path/)
    end

    it 'converts exceptions without raw backtraces' do
      exception = RuntimeError.new("boom at #{Dir.pwd}/secret")
      metadata = described_class.new.exception_metadata(exception)

      expect(metadata).to include('exception_class' => 'RuntimeError', 'backtrace' => nil)
      expect(metadata.fetch('exception_summary')).not_to include(Dir.pwd)
    end
  end

  describe RailsMmd::SafeTokens do
    it 'implements the P0 safe-token examples' do
      tokens = described_class.new

      expect(tokens.base_token('Admin::User')).to eq('ADMIN_USER')
      expect(tokens.base_token('HTTPResponseCode')).to eq('HTTP_RESPONSE_CODE')
      expect(tokens.base_token('注文Line')).to eq('LINE')
      expect(tokens.base_token('order_item')).to eq('ORDER_ITEM')
      expect(tokens.base_token('123Order')).to eq('X_123_ORDER')
      expect(tokens.base_token('!!!')).to eq('X')
    end

    it 'suffixes scoped collisions and emits a resolved warning diagnostic' do
      result = described_class.new.assign(
        [
          { source: 'Admin::User', identity: 'model:Admin::User' },
          { source: 'Admin_User', identity: 'model:Admin_User' }
        ],
        scope: { artifact_kind: 'er', domain_id: 'core', token_kind: 'entity' }
      )

      expect(result.fetch(:tokens).values).to all(match(/\AADMIN_USER_H[0-9A-F]{12}\z/))
      expect(result.fetch(:tokens).values.uniq.length).to eq(2)
      expect(result.fetch(:diagnostics).first.dig('metadata', 'resolved')).to be(true)
    end

    it 'keeps unique scoped tokens unsuffixed' do
      result = described_class.new.assign(
        [{ source: 'User', identity: 'model:User' }],
        scope: { artifact_kind: 'er', domain_id: 'core', token_kind: 'entity' }
      )

      expect(result).to eq(tokens: { 'model:User' => 'USER' }, diagnostics: [])
    end

    it 'emits a fatal diagnostic when suffix expansion cannot resolve a collision' do
      tokens = described_class.new
      allow(tokens).to receive(:collision_digest).and_return('A' * 64)

      result = tokens.assign(
        [
          { source: 'User', identity: 'model:User' },
          { source: 'User', identity: 'model:UserDuplicate' }
        ],
        scope: { artifact_kind: 'er', domain_id: 'core', token_kind: 'entity' }
      )

      expect(result.fetch(:diagnostics).first).to include(
        'code' => 'SAFE_TOKEN_COLLISION',
        'severity' => 'fatal'
      )
      expect(result.fetch(:diagnostics).first.dig('metadata', 'resolved')).to be(false)
    end

    it 'emits schema-valid collision diagnostics for every supported token kind' do
      token_kinds = %w[entity attribute relationship diagnostic comment]
      diagnostics = token_kinds.map do |token_kind|
        described_class.new.assign(
          [
            { source: 'User', identity: "first:#{token_kind}" },
            { source: 'User', identity: "second:#{token_kind}" }
          ],
          scope: { artifact_kind: 'er', domain_id: 'core', token_kind: token_kind }
        ).fetch(:diagnostics).first
      end

      expect(RailsMmd::SchemaValidator.new.valid?(:diagnostics, diagnostics_document(diagnostics))).to be(true)
    end
  end

  describe RailsMmd::Ordering do
    it 'sorts records deterministically by named keys and diagnostic tuple' do
      expect(described_class.by_key([{ 'id' => 'b' }, { 'id' => 'a' }], 'id')).to eq([{ 'id' => 'a' }, { 'id' => 'b' }])

      diagnostics = [
        { 'severity' => 'fatal', 'phase' => 'tokenization', 'code' => 'SAFE_TOKEN_COLLISION', 'subject_id' => 'c',
          'diagnostic_id' => '3' },
        { 'severity' => 'warning', 'phase' => 'tokenization', 'code' => 'SAFE_TOKEN_COLLISION', 'subject_id' => 'b',
          'diagnostic_id' => '2' },
        { 'severity' => 'error', 'phase' => 'config', 'code' => 'CONFIG_NOT_FOUND', 'subject_id' => 'a',
          'diagnostic_id' => '1' }
      ]
      expect(described_class.diagnostics(diagnostics).map { |diagnostic| diagnostic.fetch('severity') })
        .to eq(%w[fatal error warning])

      phase_conflict = [
        { 'severity' => 'error', 'phase' => 'a', 'code' => 'OUTPUT_WRITE_FAILED', 'subject_id' => 'b',
          'diagnostic_id' => '2' },
        { 'severity' => 'error', 'phase' => 'z', 'code' => 'CONFIG_NOT_FOUND', 'subject_id' => 'b',
          'diagnostic_id' => '1' }
      ]
      expect(described_class.diagnostics(phase_conflict).map { |diagnostic| diagnostic.fetch('code') })
        .to eq(%w[CONFIG_NOT_FOUND OUTPUT_WRITE_FAILED])
    end
  end

  def fixture(path)
    JSON.parse(Pathname(__dir__).join("../../fixtures/schemas/#{path}").expand_path.read)
  end

  def diagnostics_document(diagnostics)
    payload = {
      'schema_version' => 1,
      'scope' => 'domain',
      'domain_id' => 'core',
      'diagnostics' => diagnostics
    }
    payload.merge('digest_sha256' => RailsMmd::CanonicalJson.digest_sha256(payload))
  end

  def structured_identifier_metadata
    RailsMmd::Diagnostics.new.build(
      code: 'DOMAIN_MODEL_NOT_FOUND',
      message: 'missing model',
      metadata: { domain_id: 'core', ruby_constant: 'Credential::ApiKey' }
    ).fetch('metadata')
  end

  def machine_local_config_id
    RailsMmd::Diagnostics.new.build(
      code: 'CONFIG_NOT_FOUND',
      message: 'missing',
      metadata: { config_path: "#{Dir.pwd}/rails_mmd.yml" }
    ).fetch('diagnostic_id')
  end

  def relative_config_id
    RailsMmd::Diagnostics.new.build(
      code: 'CONFIG_NOT_FOUND',
      message: 'missing',
      metadata: { config_path: 'rails_mmd.yml' }
    ).fetch('diagnostic_id')
  end

  def structured_subject_id
    RailsMmd::Diagnostics.new.build(
      code: 'DOMAIN_MODEL_NOT_FOUND',
      subject_id: 'core:Credential::ApiKey:password_digest',
      message: 'missing model',
      metadata: { domain_id: 'core', ruby_constant: 'Credential::ApiKey' }
    ).fetch('subject_id')
  end

  def free_text_array_metadata
    RailsMmd::Diagnostics.new.build(
      code: 'OUTPUT_DIRECTORY_INVALID',
      message: 'bad output',
      metadata: { field_path: '$.output.directory', reason: ["#{Dir.pwd}/log.txt", 12] }
    ).fetch('metadata').fetch('reason')
  end

  def safe_token_metadata(token_kind:)
    {
      artifact_kind: 'er',
      domain_id: 'core',
      token_kind: token_kind,
      base_safe_token: 'USER',
      collision_subject_count: 2,
      resolved: true
    }
  end
end
# rubocop:enable RSpec/DescribeClass, RSpec/ExampleLength, RSpec/MultipleExpectations
