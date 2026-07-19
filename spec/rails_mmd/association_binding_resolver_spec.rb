# frozen_string_literal: true

require 'rails_mmd/association_binding_resolver'

# rubocop:disable RSpec/ExampleLength, RSpec/MultipleExpectations
RSpec.describe RailsMmd::AssociationBindingResolver do
  describe '.belongs_to' do
    it 'normalizes scalar and composite reflected bindings against the concrete target' do
      target_model = Class.new
      scalar = reflection(foreign_key: 'account_uuid', association_primary_key: 'uuid')
      composite = reflection(
        foreign_key: %w[account_tenant_id account_code],
        association_primary_key: %w[tenant_id code]
      )

      scalar_result = described_class.belongs_to(scalar, target_model: target_model)
      composite_result = described_class.belongs_to(composite, target_model: target_model)

      expect(binding_values(scalar_result)).to eq([['account_uuid'], ['uuid'], nil])
      expect(binding_values(composite_result)).to eq(
        [%w[account_tenant_id account_code], %w[tenant_id code], nil]
      )
      expect(scalar.received_target_model).to equal(target_model)
      expect(composite.received_target_model).to equal(target_model)
      expect(scalar_result).to be_success
      expect(composite_result).to be_success
    end

    it 'supports a zero-arity association primary-key reader' do
      target_model = Class.new
      reflected = reflection(foreign_key: 'account_uuid', association_primary_key: 'uuid')
      reflected.define_singleton_method(:association_primary_key) { 'uuid' }

      result = described_class.belongs_to(reflected, target_model: target_model)

      expect(binding_values(result)).to eq([['account_uuid'], ['uuid'], nil])
    end

    it 'carries the custom type column for a polymorphic binding' do
      reflected = reflection(
        foreign_key: %w[subject_tenant_id subject_code],
        association_primary_key: %w[tenant_id code],
        polymorphic: true,
        foreign_type: 'subject_kind'
      )

      result = described_class.belongs_to(reflected, target_model: Class.new)

      expect(binding_values(result)).to eq(
        [%w[subject_tenant_id subject_code], %w[tenant_id code], 'subject_kind']
      )
    end
  end

  describe '.has' do
    it 'uses the reflected owner key and falls back only when that reader returns nil' do
      explicit = reflection(foreign_key: 'account_uuid', active_record_primary_key: 'uuid')
      fallback = reflection(foreign_key: %w[tenant_id account_id], active_record_primary_key: nil)

      explicit_result = described_class.has(explicit, owner_primary_key_columns: ['id'])
      fallback_result = described_class.has(fallback, owner_primary_key_columns: %w[tenant_id id])

      expect(binding_values(explicit_result)).to eq([['account_uuid'], ['uuid'], nil])
      expect(binding_values(fallback_result)).to eq(
        [%w[tenant_id account_id], %w[tenant_id id], nil]
      )
    end

    it 'carries the inverse custom type column only for an as binding' do
      inverse = reflection(
        foreign_key: 'subject_code',
        active_record_primary_key: 'code',
        options: { as: :subject },
        type: 'subject_kind'
      )
      ordinary = reflection(foreign_key: 'account_id', active_record_primary_key: 'id', type: -> { raise 'unused' })

      inverse_result = described_class.has(inverse, owner_primary_key_columns: ['id'])
      ordinary_result = described_class.has(ordinary, owner_primary_key_columns: ['id'])

      expect(binding_values(inverse_result)).to eq([['subject_code'], ['code'], 'subject_kind'])
      expect(binding_values(ordinary_result)).to eq([['account_id'], ['id'], nil])
    end
  end

  describe '.polymorphic_root' do
    it 'returns custom identifier and scalar type columns without reading a referenced key' do
      reflected = reflection(
        foreign_key: %w[subject_tenant_id subject_code],
        foreign_type: 'subject_kind',
        association_primary_key: -> { raise 'must not resolve a target key' },
        active_record_primary_key: -> { raise 'must not resolve an owner key' }
      )

      result = described_class.polymorphic_root(reflected)

      expect(binding_values(result)).to eq([%w[subject_tenant_id subject_code], nil, 'subject_kind'])
      expect(result).to be_success
    end
  end

  describe 'invalid reflection metadata' do
    it 'closes reader exceptions, malformed tuples, unequal widths, and non-scalar type columns' do
      cases = [
        -> { described_class.belongs_to(reflection(foreign_key: -> { raise 'unreadable' }), target_model: Class.new) },
        -> { described_class.belongs_to(reflection(foreign_key: []), target_model: Class.new) },
        lambda {
          described_class.belongs_to(
            reflection(foreign_key: %w[tenant_id account_id], association_primary_key: 'id'),
            target_model: Class.new
          )
        },
        lambda {
          described_class.has(
            reflection(foreign_key: 'subject_id', options: { as: :subject }, type: ['only']),
            owner_primary_key_columns: ['id']
          )
        },
        -> { described_class.polymorphic_root(reflection(foreign_key: -> { raise 'unreadable root key' })) },
        -> { described_class.polymorphic_root(reflection(foreign_type: nil)) }
      ]

      results = cases.map(&:call)

      expect(results).to all(have_attributes(
                               binding: nil,
                               diagnostic_code: 'ASSOCIATION_COMPOSITE_KEY_OMITTED'
                             ))
      expect(results).to all(satisfy { |result| !result.success? })
    end
  end

  it 'freezes every returned key tuple and tuple member' do
    result = described_class.belongs_to(
      reflection(foreign_key: %w[account_tenant_id account_code], association_primary_key: %w[tenant_id code]),
      target_model: Class.new
    )

    tuples = [result.binding.foreign_key_columns, result.binding.referenced_key_columns]

    expect(tuples).to all(be_frozen)
    expect(tuples.flatten).to all(be_frozen)
  end

  it 'freezes successful and failed result envelopes' do
    success = described_class.belongs_to(reflection, target_model: Class.new)
    failure = described_class.polymorphic_root(reflection(foreign_type: nil))

    expect(success).to be_frozen
    expect(success.binding).to be_frozen
    expect(failure).to be_frozen
  end

  def reflection(**overrides)
    metadata = {
      foreign_key: 'account_id', association_primary_key: 'id', active_record_primary_key: 'id',
      polymorphic: false, foreign_type: 'subject_type', options: {}, type: 'subject_type'
    }.merge(overrides)
    reflected = Struct.new(:metadata, :received_target_model).new(metadata)
    define_readers(reflected)
    reflected
  end

  def binding_values(result)
    binding = result.binding
    [binding.foreign_key_columns, binding.referenced_key_columns, binding.foreign_type_column]
  end

  def define_readers(reflected)
    define_metadata_access(reflected)
    %i[foreign_key foreign_type active_record_primary_key type].each { |reader| define_value_reader(reflected, reader) }
    reflected.define_singleton_method(:options) { metadata.fetch(:options) }
    reflected.define_singleton_method(:polymorphic?) { read_metadata(:polymorphic) }
    define_association_primary_key_reader(reflected)
  end

  def define_association_primary_key_reader(reflected)
    reflected.define_singleton_method(:association_primary_key) do |target_model|
      self.received_target_model = target_model
      read_metadata(:association_primary_key)
    end
  end

  def define_metadata_access(reflected)
    reflected.define_singleton_method(:read_metadata) do |name|
      value = metadata.fetch(name)
      value.respond_to?(:call) ? value.call : value
    end
  end

  def define_value_reader(reflected, reader)
    reflected.define_singleton_method(reader) { read_metadata(reader) }
  end
end
# rubocop:enable RSpec/ExampleLength, RSpec/MultipleExpectations
