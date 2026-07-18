# frozen_string_literal: true

require 'rails_mmd/canonical_json'
require 'rails_mmd/domain_resolver'
require 'rails_mmd/relationship_builder'
require 'rails_mmd/schema_probe'
require 'rails_mmd/schema_validator'

# rubocop:disable Lint/ConstantDefinitionInBlock, Metrics/ParameterLists, RSpec/ExampleLength, RSpec/InstanceVariable, RSpec/LeakyConstantDeclaration, RSpec/MultipleExpectations
RSpec.describe RailsMmd::RelationshipBuilder do
  it 'builds eligible belongs_to relationships with conservative cardinality evidence' do
    user_model = owner_model(belongs_to('account'))
    account_model = renderable_model('Account', 'accounts')
    domain = domain_result(
      'core',
      [
        entity('User', 'users', columns: [column('id', false), column('account_id', false)],
                                foreign_keys: [foreign_key('users', 'account_id', 'accounts', 'id')],
                                indexes: [index(['account_id'], true, using: :btree)]),
        entity('Account', 'accounts', columns: [column('id', false)])
      ]
    )

    result = build(domain, 'User' => user_model, 'Account' => account_model)

    expect(result).to be_success
    expect(result.diagnostics).to eq([])
    expect(result.domains.first.relationships.map(&:relationship_id)).to eq(['relationships/users/account'])
    relationship = result.domains.first.relationships.first
    expect(relationship.owner_entity_id).to eq('entities/users')
    expect(relationship.target_entity_id).to eq('entities/accounts')
    expect(relationship.association_name).to eq('account')
    expect(relationship.owner_foreign_key_column).to eq('account_id')
    expect(relationship.target_primary_key_column).to eq('id')
    expect(relationship.owner_fk_unique).to be(true)
    expect(relationship.db_foreign_key).to be(true)
    expect(relationship.owner_fk_nullable).to be(false)
    expect(relationship.owner_cardinality).to eq('0..1')
    expect(relationship.target_cardinality).to eq('1..1')
  end

  it 'handles owner models without associations' do
    user_model = owner_model
    domain = domain_result('core', [entity('User', 'users')])

    result = build(domain, 'User' => user_model)

    expect(result.domains.first.relationships).to eq([])
    expect(result.diagnostics).to eq([])
  end

  it 'uses reflections fallback and ignores owner models that cannot resolve' do
    belongs_to_reflection = simple_reflection('account')
    ignored = ignored_reflection(:has_many)
    owner = Class.new do
      define_singleton_method(:reflections) do
        { 'account' => belongs_to_reflection, 'comments' => ignored }
      end
    end
    domain = domain_result(
      'core',
      [
        entity('User', 'users', columns: [column('id', false), column('account_id', true)]),
        entity('Account', 'accounts', columns: [column('id', false)]),
        entity('MissingOwner', 'missing_owners')
      ]
    )

    result = described_class.new(
      model_resolver: lambda { |name|
        { 'User' => owner, 'Account' => renderable_model('Account', 'accounts') }.fetch(name)
      }
    ).build(domains: [domain])

    expect(result.domains.first.relationships.map(&:association_name)).to eq(['account'])
    expect(result.diagnostics.map { |diagnostic| diagnostic.fetch('code') }).to eq(
      ['ASSOCIATION_MACRO_OMITTED']
    )
  end

  it 'reports every non-belongs-to macro without resolving its target' do
    owner = owner_model(
      association('profile', :has_one),
      association('posts', :has_many),
      association('tags', :has_and_belongs_to_many)
    )
    domain = domain_result('core', [entity('Author', 'authors')])

    result = build(domain, 'Author' => owner)

    expect(result.domains.first.relationships).to eq([])
    projected = result.diagnostics.map do |diagnostic|
      [diagnostic.fetch('subject_id'), diagnostic.fetch('code'), diagnostic.dig('metadata', 'association_macro')]
    end
    expect(projected).to contain_exactly(
      ['authors.profile', 'ASSOCIATION_MACRO_OMITTED', 'has_one'],
      ['authors.posts', 'ASSOCIATION_MACRO_OMITTED', 'has_many'],
      ['authors.tags', 'ASSOCIATION_MACRO_OMITTED', 'has_and_belongs_to_many']
    )
    expect(result.diagnostics).to all(satisfy { |diagnostic| schema_valid_diagnostic?(diagnostic) })
  end

  it 'omits ineligible belongs_to reflections with schema-valid diagnostics' do
    owner = owner_model(
      belongs_to('taggable', polymorphic: true),
      belongs_to('recent_account', scope: -> {}),
      belongs_to('missing', klass: -> { raise NameError, 'uninitialized constant Missing' }, class_name: 'Missing'),
      belongs_to('legacy_account', klass: renderable_model('LegacyAccount', 'legacy_accounts', renderable: false)),
      belongs_to('external_account', klass: renderable_model('ExternalAccount', 'external_accounts')),
      belongs_to('composite_owner', class_name: 'Account', foreign_key: %w[first_id second_id]),
      belongs_to('missing_key', class_name: 'Account', foreign_key: 'missing_account_id'),
      belongs_to('uuid_account', class_name: 'Account', association_primary_key: 'uuid'),
      belongs_to('BadName')
    )
    domain = domain_result(
      'core',
      [
        entity('Order', 'orders', columns: [column('id', false), column('account_id', true)]),
        entity('Account', 'accounts', columns: [column('id', false)])
      ]
    )

    result = build(
      domain,
      'Order' => owner,
      'Account' => renderable_model('Account', 'accounts')
    )

    expect(result.domains.first.relationships).to eq([])
    expect(result.diagnostics.map { |diagnostic| diagnostic.fetch('code') }).to eq(
      %w[
        ASSOCIATION_POLYMORPHIC_OMITTED
        ASSOCIATION_SCOPED_OMITTED
        ASSOCIATION_TARGET_UNRESOLVED
        ASSOCIATION_TARGET_NOT_RENDERABLE_OMITTED
        DOMAIN_RELATIONSHIP_OMITTED
        ASSOCIATION_COMPOSITE_KEY_OMITTED
        ASSOCIATION_KEY_COLUMN_MISSING
        ASSOCIATION_NON_PRIMARY_KEY_OMITTED
        ASSOCIATION_NAME_UNSUPPORTED_OMITTED
      ]
    )
    expect(result.diagnostics).to all(satisfy { |diagnostic| schema_valid_diagnostic?(diagnostic) })
  end

  it 'weakens cardinality when FK or unique-index evidence is absent' do
    owner = owner_model(belongs_to('account'))
    domain = domain_result(
      'core',
      [
        entity('User', 'users', columns: [column('id', false), column('account_id', true)]),
        entity('Account', 'accounts', columns: [column('id', false)])
      ]
    )

    relationship = build(domain, 'User' => owner, 'Account' => renderable_model('Account', 'accounts'))
                   .domains.first.relationships.first

    expect(relationship.owner_cardinality).to eq('0..many')
    expect(relationship.target_cardinality).to eq('0..1')
  end

  it 'does not strengthen owner cardinality from partial or expression unique indexes' do
    owner = owner_model(belongs_to('account'))
    domain = domain_result(
      'core',
      [
        entity('User', 'users', columns: [column('id', false), column('account_id', true)],
                                indexes: [
                                  index(['account_id'], true, where: 'deleted_at IS NULL'),
                                  index(['account_id'], true, expression: 'lower(account_id)')
                                ]),
        entity('Account', 'accounts', columns: [column('id', false)])
      ]
    )

    relationship = build(domain, 'User' => owner, 'Account' => renderable_model('Account', 'accounts'))
                   .domains.first.relationships.first

    expect(relationship.owner_cardinality).to eq('0..many')
  end

  it 'does not treat target model default scope as a scoped belongs_to and strips safe suffixes from names' do
    owner = owner_model(belongs_to('account?', class_name: 'Account', foreign_key: 'account_id'))
    account = renderable_model('Account', 'accounts')
    account.define_singleton_method(:default_scopes?) { true }
    domain = domain_result(
      'core',
      [
        entity('User', 'users', columns: [column('id', false), column('account_id', false)]),
        entity('Account', 'accounts', columns: [column('id', false)])
      ]
    )

    result = build(domain, 'User' => owner, 'Account' => account)

    expect(result.diagnostics).to eq([])
    expect(result.domains.first.relationships.first.association_name).to eq('account')
  end

  it 'omits targets whose renderability checks raise without leaking exceptions' do
    target = Class.new do
      def self.name = 'Account'
      def self.abstract_class? = false
      def self.base_class = self
      def self.table_name = raise 'table name unavailable'
    end
    owner = owner_model(belongs_to('account', klass: target))
    domain = domain_result(
      'core',
      [
        entity('User', 'users', columns: [column('id', false), column('account_id', true)]),
        entity('Account', 'accounts', columns: [column('id', false)])
      ]
    )

    result = build(domain, 'User' => owner)

    expect(result.diagnostics.first).to include('code' => 'ASSOCIATION_TARGET_NOT_RENDERABLE_OMITTED')
  end

  def build(domain, models)
    described_class.new(model_resolver: ->(name) { models.fetch(name) }).build(domains: [domain])
  end

  def domain_result(domain_id, entities)
    RailsMmd::SchemaProbe::DomainResult.new(domain_id: domain_id, entities: entities, diagnostics: [])
  end

  def entity(ruby_constant, table_name, columns: [column('id', false)], primary_key: 'id', foreign_keys: [],
             indexes: [])
    RailsMmd::SchemaProbe::Entity.new(
      ruby_constant: ruby_constant,
      table_name: table_name,
      connection_context_id: '{"name":"primary"}',
      columns: columns,
      primary_key: primary_key,
      foreign_keys: foreign_keys,
      indexes: indexes
    )
  end

  def column(name, nullable)
    RailsMmd::SchemaProbe::Column.new(name: name, type: :integer, nullable: nullable)
  end

  def foreign_key(from_table, column_name, to_table, primary_key)
    RailsMmd::SchemaProbe::ForeignKey.new(
      from_table: from_table,
      column: column_name,
      to_table: to_table,
      primary_key: primary_key
    )
  end

  def index(columns, unique, where: nil, using: nil, expression: nil)
    RailsMmd::SchemaProbe::Index.new(
      columns: columns,
      unique: unique,
      where: where,
      using: using,
      expression: expression
    )
  end

  def owner_model(*reflections)
    Class.new do
      define_singleton_method(:reflect_on_all_associations) do |macro = nil|
        macro ? reflections.select { |reflection| reflection.macro == macro } : reflections
      end
    end
  end

  def renderable_model(name, table_name, renderable: true)
    model = Class.new
    model.define_singleton_method(:name) { name }
    model.define_singleton_method(:abstract_class?) { !renderable }
    model.define_singleton_method(:base_class) { model }
    model.define_singleton_method(:table_name) { table_name }
    model
  end

  def belongs_to(name, options = {})
    Reflection.new(name, :belongs_to, options)
  end

  def ignored_reflection(macro)
    Reflection.new(macro.to_s, macro, {})
  end

  def association(name, macro)
    Reflection.new(name, macro, {})
  end

  def simple_reflection(name)
    Struct.new(:name, :macro, :foreign_key, :association_primary_key) do
      def polymorphic? = false

      def scope = nil
    end.new(name, :belongs_to, "#{name}_id", 'id')
  end

  class Reflection
    attr_reader :name, :macro

    def initialize(name, macro, options)
      @name = name
      @macro = macro
      @options = options
    end

    def polymorphic? = @options.fetch(:polymorphic, false)

    def scope = @options[:scope]

    def foreign_key = @options.fetch(:foreign_key, "#{name}_id")

    def association_primary_key = @options.fetch(:association_primary_key, 'id')

    def class_name = @options.fetch(:class_name, name.split('_').map(&:capitalize).join)

    def klass
      value = @options.fetch(:klass) { raise KeyError }
      value.respond_to?(:call) ? value.call : value
    rescue KeyError
      raise NameError, "uninitialized constant #{class_name}"
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
# rubocop:enable Lint/ConstantDefinitionInBlock, Metrics/ParameterLists, RSpec/ExampleLength, RSpec/InstanceVariable, RSpec/LeakyConstantDeclaration, RSpec/MultipleExpectations
