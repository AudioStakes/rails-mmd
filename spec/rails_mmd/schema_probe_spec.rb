# frozen_string_literal: true

require 'rails_mmd/canonical_json'
require 'rails_mmd/domain_resolver'
require 'rails_mmd/model_inventory'
require 'rails_mmd/schema_probe'
require 'rails_mmd/schema_validator'

# rubocop:disable RSpec/ExampleLength, RSpec/MultipleExpectations
RSpec.describe RailsMmd::SchemaProbe do
  it 'reads table, column, primary-key, foreign-key, and unique-index metadata for selected entities only' do
    user = model(
      table_exists: true,
      columns: [column('id', :integer, false), column('account_id', :integer, true)],
      primary_key: 'id',
      foreign_keys: [foreign_key('users', 'account_id', 'accounts', 'id')],
      indexes: [index(%w[email], true)]
    )
    outside = model(table_exists: -> { raise 'domain-outside table must not be read' })
    resolver = { 'User' => user, 'Outside' => outside }
    domain = domain_result('core', [record('User')])

    result = described_class.new(model_resolver: ->(name) { resolver.fetch(name) }).probe(domains: [domain])

    expect(result).to be_success
    expect(result.exit_code).to eq(0)
    expect(result.diagnostics).to eq([])
    expect(result.domains.first.entities.map(&:ruby_constant)).to eq(['User'])
    entity = result.domains.first.entities.first
    expect(entity.columns.map(&:name)).to eq(%w[id account_id])
    expect(entity.primary_key).to eq('id')
    expect(entity.foreign_keys.map(&:column)).to eq(['account_id'])
    expect(entity.indexes.map(&:unique)).to eq([true])
  end

  it 'guards only selected renderable entity connection contexts' do
    first = record('User', connection_context_id: '{"name":"primary","role":"writing","shard":"default"}')
    second = record('Account', connection_context_id: '{"name":"animals","role":"writing","shard":"default"}')
    outside = record('Outside', connection_context_id: '{"name":"outside","role":"writing","shard":"default"}')
    domain = domain_result('core', [first, second])
    calls = []

    result = described_class.new(model_resolver: ->(name) { calls << name }).probe(domains: [domain])

    expect(result).not_to be_success
    expect(result.exit_code).to eq(2)
    expect(result.diagnostics.first).to include('code' => 'MULTI_DB_UNSUPPORTED')
    expect(result.diagnostics.first.dig('metadata', 'connection_context_ids')).to eq(
      [second.connection_context_id, first.connection_context_id].sort
    )
    expect(schema_valid_diagnostic?(result.diagnostics.first)).to be(true)
    expect(calls).to eq([])
    expect(outside.connection_context_id).to include('outside')
  end

  it 'emits fatal table and primary key diagnostics for selected model failures' do
    missing = model(table_exists: false)
    composite = model(table_exists: true, columns: [column('id', :integer, false)], primary_key: %w[id tenant_id])
    resolver = { 'MissingTable' => missing, 'CompositeKey' => composite }
    domain = domain_result('core', [record('MissingTable'), record('CompositeKey')])

    result = described_class.new(model_resolver: ->(name) { resolver.fetch(name) }).probe(domains: [domain])

    expect(result).not_to be_success
    expect(result.exit_code).to eq(2)
    expect(result.diagnostics.map { |diagnostic| diagnostic.fetch('code') }).to eq(
      %w[MODEL_TABLE_MISSING MODEL_PRIMARY_KEY_UNSUPPORTED]
    )
    expect(result.diagnostics).to all(satisfy { |diagnostic| schema_valid_diagnostic?(diagnostic) })
    expect(result.domains.first.entities).to eq([])
  end

  it 'degrades optional foreign-key and unique-index metadata without strengthening evidence' do
    user = model(
      table_exists: true,
      columns: [column('id', :integer, false)],
      primary_key: 'id',
      foreign_keys: -> { raise 'fk permission denied at /Users/dev/app' },
      indexes: -> { raise 'index permission denied' }
    )
    domain = domain_result('core', [record('User')])

    result = described_class.new(model_resolver: ->(_name) { user }).probe(domains: [domain])

    expect(result).to be_success
    expect(result.exit_code).to eq(0)
    expect(result.domains.first.entities.first.foreign_keys).to eq([])
    expect(result.domains.first.entities.first.indexes).to eq([])
    expect(result.diagnostics.map { |diagnostic| diagnostic.fetch('code') }).to eq(
      %w[DB_METADATA_DEGRADED DB_METADATA_DEGRADED]
    )
    expect(result.diagnostics.map { |diagnostic| diagnostic.dig('metadata', 'metadata_kind') })
      .to eq(%w[foreign_key unique_index])
    expect(result.diagnostics.first.dig('metadata', 'reason')).not_to include('/Users/dev')
    expect(result.diagnostics).to all(satisfy { |diagnostic| schema_valid_diagnostic?(diagnostic) })
  end

  def domain_result(domain_id, records)
    RailsMmd::DomainResolver::DomainResult.new(domain_id: domain_id, records: records, diagnostics: [])
  end

  def record(ruby_constant, connection_context_id: '{"name":"primary","role":"writing","shard":"default"}')
    RailsMmd::ModelInventory::Record.new(
      ruby_constant: ruby_constant,
      abstract_class: false,
      base_class: ruby_constant,
      table_name: "#{ruby_constant.downcase}s",
      connection_context_id: connection_context_id,
      renderable: true,
      renderability_reason: nil
    )
  end

  def model(table_exists:, columns: [], primary_key: 'id', foreign_keys: [], indexes: [])
    Class.new do
      define_singleton_method(:table_exists?) { callable_value(table_exists) }
      define_singleton_method(:columns) { callable_value(columns) }
      define_singleton_method(:primary_key) { callable_value(primary_key) }
      define_singleton_method(:foreign_keys) { callable_value(foreign_keys) }
      define_singleton_method(:indexes) { callable_value(indexes) }

      def self.callable_value(value)
        value.respond_to?(:call) ? value.call : value
      end
    end
  end

  def column(name, type, nullable)
    Struct.new(:name, :type, :null).new(name, type, nullable)
  end

  def foreign_key(from_table, column, to_table, primary_key)
    Struct.new(:from_table, :column, :to_table, :primary_key).new(from_table, column, to_table, primary_key)
  end

  def index(columns, unique)
    Struct.new(:columns, :unique).new(columns, unique)
  end

  def schema_valid_diagnostic?(diagnostic)
    envelope = {
      'schema_version' => 1,
      'scope' => 'domain',
      'domain_id' => diagnostic.fetch('metadata').fetch('domain_id'),
      'diagnostics' => [diagnostic],
      'digest_sha256' => RailsMmd::CanonicalJson.digest_sha256(diagnostic)
    }

    RailsMmd::SchemaValidator.new.valid?(:diagnostics, envelope)
  end
end
# rubocop:enable RSpec/ExampleLength, RSpec/MultipleExpectations
