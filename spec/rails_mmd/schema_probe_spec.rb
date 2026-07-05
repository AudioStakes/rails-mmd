# frozen_string_literal: true

require 'rails_mmd/canonical_json'
require 'rails_mmd/domain_resolver'
require 'rails_mmd/model_inventory'
require 'rails_mmd/relationship_builder'
require 'rails_mmd/schema_probe'
require 'rails_mmd/schema_validator'

# rubocop:disable RSpec/ExampleLength, RSpec/MultipleExpectations
RSpec.describe RailsMmd::SchemaProbe do
  it 'reads table, column, primary-key, foreign-key, and unique-index metadata for selected entities only' do
    user = model(
      table_exists: true,
      columns: [column('id', :integer, false), column('account_id', :integer, true), column('email', :string, true)],
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
    expect(entity.columns.map(&:name)).to eq(%w[id account_id email])
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

  it 'sanitizes multi-db connection context IDs before diagnostics output' do
    first = record('User', connection_context_id: '{"name":"/Users/dev/app","role":"writing","shard":"default"}')
    second = record('Account', connection_context_id: '{"name":"SECRET_TOKEN_1234","role":"writing","shard":"default"}')

    result = described_class.new(model_resolver: ->(_name) { raise 'must not probe' }).probe(
      domains: [domain_result('core', [first, second])]
    )

    ids = result.diagnostics.first.dig('metadata', 'connection_context_ids')
    expect(ids.join(' ')).not_to include('/Users/dev', 'SECRET_TOKEN_1234')
    expect(schema_valid_diagnostic?(result.diagnostics.first)).to be(true)
  end

  it 'detects multi-db even when redaction collapses distinct context IDs' do
    first = record('User', connection_context_id: '{"database":"/Users/dev/app_one"}')
    second = record('Account', connection_context_id: '{"database":"/tmp/app_two"}')

    result = described_class.new(model_resolver: ->(_name) { raise 'must not probe' }).probe(
      domains: [domain_result('core', [first, second])]
    )

    expect(result).not_to be_success
    expect(result.diagnostics.first).to include('code' => 'MULTI_DB_UNSUPPORTED')
    expect(result.diagnostics.first.dig('metadata', 'connection_context_ids').length).to eq(2)
    expect(result.diagnostics.first.dig('metadata', 'connection_context_ids').join(' '))
      .not_to include('/Users/dev', '/tmp')
  end

  it 'detects multi-db after inventory preserves distinct structured database identifiers' do
    user = inventory_model('User', database: '/Users/dev/app/db/primary.sqlite3')
    account = inventory_model('Account', database: '/tmp/other.sqlite3')
    inventory_records = RailsMmd::ModelInventory.new(
      active_record_base: Struct.new(:descendants).new([user, account]),
      constant_resolver: ->(name) { { 'User' => user, 'Account' => account }.fetch(name) }
    ).records
    domain = domain_result('core', inventory_records)

    result = described_class.new(model_resolver: ->(_name) { raise 'must not probe' }).probe(domains: [domain])

    expect(result).not_to be_success
    expect(result.diagnostics.first).to include('code' => 'MULTI_DB_UNSUPPORTED')
    expect(result.diagnostics.first.dig('metadata', 'connection_context_ids').join(' '))
      .not_to include('/Users/dev', '/tmp')
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

  it 'treats required metadata exceptions as fatal selected model diagnostics' do
    table_error = model(table_exists: -> { raise 'table denied' })
    column_error = model(table_exists: true, columns: -> { raise 'columns denied' })
    primary_key_error = model(
      table_exists: true,
      columns: [column('id', :integer, false)],
      primary_key: -> { raise 'primary key denied' }
    )
    resolver = { 'TableError' => table_error, 'ColumnError' => column_error, 'PrimaryKeyError' => primary_key_error }

    result = described_class.new(model_resolver: ->(name) { resolver.fetch(name) }).probe(
      domains: [domain_result('core', [record('TableError'), record('ColumnError'), record('PrimaryKeyError')])]
    )

    expect(result).not_to be_success
    expect(result.diagnostics.map { |diagnostic| diagnostic.fetch('code') }).to eq(
      %w[MODEL_TABLE_MISSING MODEL_TABLE_MISSING MODEL_PRIMARY_KEY_UNSUPPORTED]
    )
  end

  it 'contains selected model resolver failures as scoped table metadata failures' do
    domain = domain_result('core', [record('User')])

    result = described_class.new(model_resolver: ->(_name) { raise 'autoload failed at /Users/dev/app' }).probe(
      domains: [domain]
    )

    expect(result).not_to be_success
    expect(result.diagnostics.first).to include('code' => 'MODEL_TABLE_MISSING')
    expect(result.diagnostics.first.fetch('message')).not_to include('/Users/dev')
    expect(schema_valid_diagnostic?(result.diagnostics.first)).to be(true)
  end

  it 'contains selected model load and syntax errors as scoped table metadata failures' do
    [LoadError, SyntaxError].each do |error_class|
      result = described_class.new(
        model_resolver: ->(_name) { raise error_class, '/Users/dev/app failed' }
      ).probe(domains: [domain_result('core', [record('User')])])

      expect(result).not_to be_success
      expect(result.diagnostics.first).to include('code' => 'MODEL_TABLE_MISSING')
      expect(result.diagnostics.first.fetch('message')).not_to include('/Users/dev')
    end
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

  it 'degrades optional metadata load and syntax errors without leaking raw paths' do
    [LoadError, SyntaxError].each do |error_class|
      user = model(
        table_exists: true,
        columns: [column('id', :integer, false)],
        primary_key: 'id',
        foreign_keys: -> { raise error_class, '/Users/dev/fk failed' }
      )

      result = described_class.new(model_resolver: ->(_name) { user }).probe(
        domains: [domain_result('core', [record('User')])]
      )

      expect(result).to be_success
      expect(result.diagnostics.first).to include('code' => 'DB_METADATA_DEGRADED')
      expect(result.diagnostics.first.dig('metadata', 'reason')).not_to include('/Users/dev')
    end
  end

  it 'degrades adapter NotImplementedError from optional foreign-key and index metadata' do
    user = model(
      table_exists: true,
      columns: [column('id', :integer, false)],
      primary_key: 'id',
      foreign_keys: -> { raise NotImplementedError, 'foreign keys unsupported' },
      indexes: -> { raise NotImplementedError, 'indexes unsupported' }
    )

    result = described_class.new(model_resolver: ->(_name) { user }).probe(
      domains: [domain_result('core', [record('User')])]
    )

    expect(result).to be_success
    expect(result.diagnostics.map { |diagnostic| diagnostic.fetch('code') }).to eq(
      %w[DB_METADATA_DEGRADED DB_METADATA_DEGRADED]
    )
    expect(result.diagnostics.map { |diagnostic| diagnostic.dig('metadata', 'metadata_kind') })
      .to eq(%w[foreign_key unique_index])
  end

  it 'degrades missing adapter metadata APIs instead of treating evidence as absent' do
    user = model(table_exists: true, columns: [column('id', :integer, false), column('email', :string, true)],
                 primary_key: 'id',
                 foreign_keys: :undefined, indexes: :undefined)
    domain = domain_result('core', [record('User')])

    result = described_class.new(model_resolver: ->(_name) { user }).probe(domains: [domain])

    expect(result).to be_success
    expect(result.domains.first.entities.first.foreign_keys).to eq([])
    expect(result.domains.first.entities.first.indexes).to eq([])
    expect(result.diagnostics.map { |diagnostic| diagnostic.dig('metadata', 'metadata_kind') })
      .to eq(%w[foreign_key unique_index])
  end

  it 'reads foreign-key and index metadata from the connection when model APIs are absent' do
    user = model(table_exists: true, columns: [column('id', :integer, false), column('email', :string, true)],
                 primary_key: 'id',
                 foreign_keys: :undefined, indexes: :undefined)
    connection = Struct.new(:foreign_keys_payload, :indexes_payload) do
      def foreign_keys(_table_name) = foreign_keys_payload
      def indexes(_table_name) = indexes_payload
    end.new(
      [foreign_key('users', 'account_id', 'accounts', 'id')],
      [index(%w[email], true)]
    )
    user.define_singleton_method(:connection) { connection }

    result = described_class.new(model_resolver: ->(_name) { user }).probe(
      domains: [domain_result('core', [record('User')])]
    )

    entity = result.domains.first.entities.first
    expect(result).to be_success
    expect(entity.foreign_keys.map(&:column)).to eq(['account_id'])
    expect(entity.indexes.map(&:columns)).to eq([%w[email]])
  end

  it 'degrades inconsistent foreign-key and index metadata instead of handing it to relationship cardinality' do
    user = model(
      table_exists: true,
      columns: [column('id', :integer, false)],
      primary_key: 'id',
      foreign_keys: [foreign_key('users', nil, 'accounts', 'id')],
      indexes: [index(['account_id'], nil)]
    )

    result = described_class.new(model_resolver: ->(_name) { user }).probe(
      domains: [domain_result('core', [record('User')])]
    )

    expect(result).to be_success
    expect(result.domains.first.entities.first.foreign_keys).to eq([])
    expect(result.domains.first.entities.first.indexes).to eq([])
    expect(result.diagnostics.map { |diagnostic| diagnostic.fetch('code') }).to eq(
      %w[DB_METADATA_DEGRADED DB_METADATA_DEGRADED]
    )
    expect(result.diagnostics.map { |diagnostic| diagnostic.dig('metadata', 'metadata_kind') })
      .to eq(%w[foreign_key unique_index])
  end

  it 'preserves optional plain and partial index evidence as closed scalar metadata' do
    indexes = [
      index(['account_id'], true, using: :btree),
      index(['account_id'], true, where: 'deleted_at IS NULL'),
      index(['account_id'], true, expression: 'account_id')
    ]
    user = model(
      table_exists: true,
      columns: [column('id', :integer, false), column('account_id', :integer, true)],
      primary_key: 'id',
      indexes: indexes
    )

    result = described_class.new(model_resolver: ->(_name) { user }).probe(
      domains: [domain_result('core', [record('User')])]
    )

    expect(result).to be_success
    expect(result.diagnostics).to eq([])
    expect(result.domains.first.entities.first.indexes.map(&:where)).to eq([nil, 'deleted_at IS NULL', nil])
    expect(result.domains.first.entities.first.indexes.map(&:using)).to eq(['btree', nil, nil])
    expect(result.domains.first.entities.first.indexes.map(&:expression)).to eq([nil, nil, 'account_id'])
  end

  it 'degrades expression-column and non-scalar index metadata instead of leaking raw adapter values' do
    indexes = [
      index(['LOWER(account_id)'], true),
      index(['account_id'], true, expression: Object.new)
    ]
    user = model(
      table_exists: true,
      columns: [column('id', :integer, false), column('account_id', :integer, true)],
      primary_key: 'id',
      indexes: indexes
    )

    result = described_class.new(model_resolver: ->(_name) { user }).probe(
      domains: [domain_result('core', [record('User')])]
    )

    expect(result).to be_success
    expect(result.domains.first.entities.first.indexes).to eq([])
    expect(result.diagnostics.map { |diagnostic| diagnostic.dig('metadata', 'metadata_kind') }).to eq(
      ['unique_index']
    )
  end

  it 'keeps valid metadata records when unrelated optional records are malformed' do
    user = model(
      table_exists: true,
      columns: [column('id', :integer, false), column('account_id', :integer, true)],
      primary_key: 'id',
      foreign_keys: [
        foreign_key('users', 'account_id', 'accounts', 'id'),
        foreign_key('users', nil, 'accounts', 'id')
      ],
      indexes: [
        index(['account_id'], true, using: :btree),
        index(['LOWER(account_id)'], true)
      ]
    )

    result = described_class.new(model_resolver: ->(_name) { user }).probe(
      domains: [domain_result('core', [record('User')])]
    )

    entity = result.domains.first.entities.first
    expect(entity.foreign_keys.map(&:column)).to eq(['account_id'])
    expect(entity.indexes.map(&:columns)).to eq([['account_id']])
    expect(result.diagnostics.map { |diagnostic| diagnostic.dig('metadata', 'metadata_kind') })
      .to eq(%w[foreign_key unique_index])
  end

  it 'keeps probe-to-relationship cardinality weak for partial index evidence' do
    user = model(
      table_exists: true,
      columns: [column('id', :integer, false), column('account_id', :integer, true)],
      primary_key: 'id',
      indexes: [index(['account_id'], true, where: 'deleted_at IS NULL')]
    )
    account = model(table_exists: true, columns: [column('id', :integer, false)], primary_key: 'id')
    probe_result = described_class.new(model_resolver: lambda { |name|
      { 'User' => user, 'Account' => account }.fetch(name)
    })
                                  .probe(domains: [domain_result('core', [record('User'), record('Account')])])
    user_owner = owner_model(belongs_to('account'))
    account_target = relationship_target_model('Account', 'accounts')

    relationship = RailsMmd::RelationshipBuilder.new(
      model_resolver: ->(name) { { 'User' => user_owner, 'Account' => account_target }.fetch(name) }
    ).build(domains: probe_result.domains).domains.first.relationships.first

    expect(relationship.owner_cardinality).to eq('0..many')
  end

  it 'keeps probe-to-relationship cardinality weak for non-btree index evidence' do
    user = model(
      table_exists: true,
      columns: [column('id', :integer, false), column('account_id', :integer, true)],
      primary_key: 'id',
      indexes: [index(['account_id'], true, using: :gin)]
    )
    account = model(table_exists: true, columns: [column('id', :integer, false)], primary_key: 'id')
    probe_result = described_class.new(model_resolver: lambda { |name|
      { 'User' => user, 'Account' => account }.fetch(name)
    })
                                  .probe(domains: [domain_result('core', [record('User'), record('Account')])])
    user_owner = owner_model(belongs_to('account'))
    account_target = relationship_target_model('Account', 'accounts')

    relationship = RailsMmd::RelationshipBuilder.new(
      model_resolver: ->(name) { { 'User' => user_owner, 'Account' => account_target }.fetch(name) }
    ).build(domains: probe_result.domains).domains.first.relationships.first

    expect(relationship.owner_cardinality).to eq('0..many')
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
    model_class = base_model(table_exists, columns, primary_key)
    define_optional_schema_method(model_class, :foreign_keys, foreign_keys)
    define_optional_schema_method(model_class, :indexes, indexes)
    model_class
  end

  def base_model(table_exists, columns, primary_key)
    Class.new do
      define_singleton_method(:table_exists?) { callable_value(table_exists) }
      define_singleton_method(:columns) { callable_value(columns) }
      define_singleton_method(:primary_key) { callable_value(primary_key) }

      def self.callable_value(value)
        value.respond_to?(:call) ? value.call : value
      end
    end
  end

  def define_optional_schema_method(model_class, method_name, value)
    return if value == :undefined

    model_class.define_singleton_method(method_name) do
      model_class.callable_value(value)
    end
  end

  def column(name, type, nullable)
    Struct.new(:name, :type, :null).new(name, type, nullable)
  end

  def foreign_key(from_table, column, to_table, primary_key)
    Struct.new(:from_table, :column, :to_table, :primary_key).new(from_table, column, to_table, primary_key)
  end

  def index(columns, unique, where: nil, using: nil, expression: nil)
    Struct.new(:columns, :unique, :where, :using, :expression).new(columns, unique, where, using, expression)
  end

  def owner_model(*reflections)
    Class.new do
      define_singleton_method(:reflect_on_all_associations) do |macro|
        raise 'only belongs_to should be requested' unless macro == :belongs_to

        reflections
      end
    end
  end

  def belongs_to(name)
    Struct.new(:name, :macro, :foreign_key, :association_primary_key, :class_name) do
      def polymorphic? = false

      def scope = nil
    end.new(name, :belongs_to, "#{name}_id", 'id', name.capitalize)
  end

  def relationship_target_model(name, table_name)
    model = Class.new
    model.define_singleton_method(:name) { name }
    model.define_singleton_method(:abstract_class?) { false }
    model.define_singleton_method(:base_class) { model }
    model.define_singleton_method(:table_name) { table_name }
    model
  end

  def inventory_model(name, database:)
    model = Class.new
    model.define_singleton_method(:name) { name }
    model.define_singleton_method(:abstract_class?) { false }
    model.define_singleton_method(:base_class) { model }
    model.define_singleton_method(:table_name) { "#{name.downcase}s" }
    define_db_config(model, database)
    model
  end

  def define_db_config(model, database)
    model.define_singleton_method(:connection_db_config) do
      Struct.new(:name, :adapter, :database, :host, :port, :username).new(
        'primary', 'sqlite3', database, nil, nil, nil
      )
    end
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
