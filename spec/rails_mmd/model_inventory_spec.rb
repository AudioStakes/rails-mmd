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
                 connection_context: { name: 'primary' }, table_error: nil)
    model = Class.new
    model.define_singleton_method(:name) { name }
    model.define_singleton_method(:abstract_class?) { abstract }
    model.define_singleton_method(:base_class) { base_class || model }
    model.define_singleton_method(:connection_context) { connection_context }
    model.define_singleton_method(:table_name) do
      raise table_error if table_error

      table_name
    end
    model
  end
  # rubocop:enable Metrics/ParameterLists

  def default_table_name(name)
    return nil unless name

    "#{name.downcase}s"
  end
end
# rubocop:enable RSpec/ExampleLength, RSpec/MultipleExpectations
