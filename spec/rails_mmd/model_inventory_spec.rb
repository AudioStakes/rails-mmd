# frozen_string_literal: true

require 'rails_mmd/model_inventory'

# rubocop:disable RSpec/ExampleLength, RSpec/MultipleExpectations
RSpec.describe RailsMmd::ModelInventory do
  it 'inventories only named descendants whose constants resolve to the same class' do
    user = fake_model('User')
    anonymous = fake_model(nil)
    blank = fake_model('')
    unresolved = fake_model('MissingModel')
    mismatched = fake_model('OtherModel')
    other = fake_model('OtherModel')

    records = inventory_for([user, anonymous, blank, unresolved, mismatched], constants: {
                              'User' => user,
                              'OtherModel' => other
                            }).records

    expect(records.map(&:ruby_constant)).to eq(['User'])
  end

  it 'ignores descendants whose constant resolution raises load failures' do
    user = fake_model('User')
    broken = fake_model('BrokenAutoload')
    resolver = lambda do |name|
      raise LoadError, name if name == 'BrokenAutoload'

      user
    end

    records = described_class.new(
      active_record_base: Struct.new(:descendants).new([user, broken]),
      constant_resolver: resolver
    ).records

    expect(records.map(&:ruby_constant)).to eq(['User'])
  end

  it 'ignores descendants whose constant resolution raises script errors' do
    broken = fake_model('BrokenAutoload')
    resolver = ->(_name) { raise NotImplementedError, 'autoload hook unavailable' }

    records = described_class.new(
      active_record_base: Struct.new(:descendants).new([broken]),
      constant_resolver: resolver
    ).records

    expect(records).to eq([])
  end

  it 'propagates resource failures while resolving descendants' do
    broken = fake_model('BrokenAutoload')
    resolver = ->(_name) { raise NoMemoryError, 'resource exhausted' }
    inventory = described_class.new(
      active_record_base: Struct.new(:descendants).new([broken]),
      constant_resolver: resolver
    )

    expect { inventory.records }.to raise_error(NoMemoryError, 'resource exhausted')
  end

  it 'records exactly the contract inventory fields for renderable base models' do
    user = fake_model(
      'User',
      table_name: 'users',
      connection_context: { name: 'primary', role: 'writing', shard: :default, password: 'secret' }
    )

    record = inventory_for([user], constants: { 'User' => user }).records.fetch(0)

    expect(record.members).to eq(%i[
                                   ruby_constant
                                   abstract_class
                                   base_class
                                   table_name
                                   connection_context_id
                                   renderable
                                   renderability_reason
                                 ])
    expect(record.to_h).to include(
      ruby_constant: 'User',
      abstract_class: false,
      base_class: 'User',
      table_name: 'users',
      renderable: true,
      renderability_reason: nil
    )
    expect(record.connection_context_id).to include('primary', 'writing')
    expect(record.connection_context_id).not_to include('secret')
  end

  it 'uses only the contract key set for connection context IDs' do
    first = fake_model(
      'User',
      connection_context: {
        name: 'primary',
        role: 'writing',
        adapter: 'postgresql',
        database: 'app',
        password: 'secret-one',
        replica: true
      }
    )
    second = fake_model(
      'Account',
      connection_context: {
        name: 'primary',
        role: 'writing',
        adapter: 'postgresql',
        database: 'app',
        password: 'secret-two',
        replica: false
      }
    )

    records = inventory_for([first, second], constants: { 'User' => first, 'Account' => second }).records
    payload = JSON.parse(records.first.connection_context_id)

    expect(payload.keys).to eq(%w[adapter database host name port role shard username])
    expect(payload).to include('role' => 'writing', 'shard' => 'default')
    expect(records.map(&:connection_context_id).uniq.size).to eq(1)
    expect(records.first.connection_context_id).not_to include('password', 'secret', 'replica')
  end

  it 'builds connection context IDs from db config when no explicit context exists' do
    user = fake_model_without_connection_context(
      'User',
      db_config: Struct.new(:name, :adapter, :database, :host, :port, :username).new(
        'primary', 'postgresql', 'app', 'localhost', 5432, 'app_user'
      )
    )

    record = inventory_for([user], constants: { 'User' => user }).records.fetch(0)
    payload = JSON.parse(record.connection_context_id)

    expect(payload).to eq(
      'adapter' => 'postgresql',
      'database' => 'app',
      'host' => 'localhost',
      'name' => 'primary',
      'port' => 5432,
      'role' => 'default',
      'shard' => 'default',
      'username' => 'app_user'
    )
  end

  it 'preserves non-secret database identifiers for connection guard comparisons' do
    first = fake_model_without_connection_context(
      'User',
      db_config: Struct.new(:name, :adapter, :database, :host, :port, :username).new(
        'primary', 'sqlite3', '/Users/dev/app/db/primary.sqlite3', nil, nil, nil
      )
    )
    second = fake_model_without_connection_context(
      'Account',
      db_config: Struct.new(:name, :adapter, :database, :host, :port, :username).new(
        'primary', 'sqlite3', '/tmp/other.sqlite3', nil, nil, nil
      )
    )

    records = inventory_for([first, second], constants: { 'User' => first, 'Account' => second }).records

    expect(records.map(&:connection_context_id).uniq.size).to eq(2)
    expect(records.first.connection_context_id).to include('/Users/dev/app/db/primary.sqlite3')
    expect(records.last.connection_context_id).to include('/tmp/other.sqlite3')
  end

  it 'falls back to the model name when no connection context API is available' do
    user = fake_model_without_connection_context('User', db_config: nil)

    record = inventory_for([user], constants: { 'User' => user }).records.fetch(0)

    expect(JSON.parse(record.connection_context_id)).to eq('model' => 'User')
  end

  it 'resolves constants through Object by default' do
    stub_const('InventorySpecModel', fake_model('InventorySpecModel'))

    records = described_class.new(active_record_base: Struct.new(:descendants).new([InventorySpecModel])).records

    expect(records.map(&:ruby_constant)).to eq(['InventorySpecModel'])
  end

  it 'accepts resolver objects that expose the shared resolve interface' do
    user = fake_model('User')
    resolver = Object.new
    resolver.define_singleton_method(:resolve) { |name| { 'User' => user }.fetch(name) }

    records = described_class.new(
      active_record_base: Struct.new(:descendants).new([user]),
      constant_resolver: resolver
    ).records

    expect(records.map(&:ruby_constant)).to eq(['User'])
  end

  it 'marks abstract models and STI subclasses non-renderable when observable' do
    base = fake_model('Animal')
    abstract_model = fake_model('ApplicationRecord', abstract: true)
    subclass = fake_model('Dog', base_class: base)

    records = inventory_for(
      [base, abstract_model, subclass],
      constants: { 'Animal' => base, 'ApplicationRecord' => abstract_model, 'Dog' => subclass }
    ).records

    expect(records.map { |record| [record.ruby_constant, record.renderable, record.renderability_reason] })
      .to contain_exactly(
        ['Animal', true, nil],
        ['ApplicationRecord', false, 'abstract_class'],
        ['Dog', false, 'sti_subclass']
      )
  end

  it 'represents table-name failures as non-renderable records' do
    broken = fake_model('BrokenModel', table_error: RuntimeError.new('/Users/dev/table boom'))

    record = inventory_for([broken], constants: { 'BrokenModel' => broken }).records.fetch(0)

    expect(record.ruby_constant).to eq('BrokenModel')
    expect(record.table_name).to be_nil
    expect(record.renderable).to be(false)
    expect(record.renderability_reason).to include('table_name_unavailable')
    expect(record.renderability_reason).not_to include('/Users/dev')
  end

  it 'contains connection-context failures as non-renderable records with a deterministic fallback' do
    broken = fake_model('BrokenConnection', connection_error: RuntimeError.new('/Users/dev/password=secret'))

    record = inventory_for([broken], constants: { 'BrokenConnection' => broken }).records.fetch(0)

    expect(record.ruby_constant).to eq('BrokenConnection')
    expect(record.connection_context_id).to eq(JSON.generate('model' => 'BrokenConnection'))
    expect(record.renderable).to be(false)
    expect(record.renderability_reason).to include('connection_context_unavailable')
    expect(record.renderability_reason).not_to include('/Users/dev', 'secret')
  end

  it 'still records abstract models when connection context is unavailable' do
    abstract_model = fake_model(
      'ApplicationRecord',
      abstract: true,
      connection_error: RuntimeError.new('abstract connection unavailable')
    )

    record = inventory_for(
      [abstract_model],
      constants: { 'ApplicationRecord' => abstract_model }
    ).records.fetch(0)

    expect(record.ruby_constant).to eq('ApplicationRecord')
    expect(record.connection_context_id).to eq(JSON.generate('model' => 'ApplicationRecord'))
    expect(record.renderable).to be(false)
    expect(record.renderability_reason).to eq('abstract_class')
  end

  it 'does not read schema metadata while inventorying models outside any resolved domain' do
    untouched = fake_model('UntouchedModel')
    %i[table_exists? columns indexes foreign_keys primary_key].each do |method_name|
      untouched.define_singleton_method(method_name) { raise "schema method #{method_name} was called" }
    end

    records = inventory_for([untouched], constants: { 'UntouchedModel' => untouched }).records

    expect(records.map(&:ruby_constant)).to eq(['UntouchedModel'])
  end

  def inventory_for(models, constants:)
    described_class.new(
      active_record_base: Struct.new(:descendants).new(models),
      constant_resolver: ->(name) { constants.fetch(name) { raise NameError, name } }
    )
  end

  # rubocop:disable Metrics/ParameterLists
  def fake_model(name, table_name: default_table_name(name), base_class: nil, abstract: false,
                 connection_context: { name: 'primary' }, connection_error: nil, table_error: nil)
    model = Class.new
    model.define_singleton_method(:name) { name }
    model.define_singleton_method(:abstract_class?) { abstract }
    model.define_singleton_method(:base_class) { base_class || model }
    define_connection_context(model, connection_context, connection_error)
    define_table_name(model, table_name, table_error)
    model
  end
  # rubocop:enable Metrics/ParameterLists

  def define_connection_context(model, connection_context, connection_error)
    model.define_singleton_method(:connection_context) do
      raise connection_error if connection_error

      connection_context
    end
  end

  def define_table_name(model, table_name, table_error)
    model.define_singleton_method(:table_name) do
      raise table_error if table_error

      table_name
    end
  end

  def fake_model_without_connection_context(name, db_config:)
    model = fake_model(name)
    class << model
      remove_method :connection_context
    end
    model.define_singleton_method(:connection_db_config) { db_config } if db_config
    model
  end

  def default_table_name(name)
    return nil unless name

    "#{name.downcase}s"
  end
end
# rubocop:enable RSpec/ExampleLength, RSpec/MultipleExpectations
