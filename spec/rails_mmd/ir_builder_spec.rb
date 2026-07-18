# frozen_string_literal: true

require 'rails_mmd/canonical_json'
require 'rails_mmd/ir_builder'
require 'rails_mmd/relationship_builder'
require 'rails_mmd/schema_probe'
require 'rails_mmd/schema_validator'

# rubocop:disable Metrics/MethodLength, RSpec/ExampleLength, RSpec/MultipleExpectations
RSpec.describe RailsMmd::IrBuilder do
  it 'normalizes selected entities and relationships into schema-valid deterministic IR' do
    domain = RailsMmd::SchemaProbe::DomainResult.new(
      domain_id: 'core',
      entities: [
        entity('User', 'users', columns: [column('id'), column('account_id')]),
        entity('Account', 'accounts')
      ],
      diagnostics: [diagnostic('d_db_metadata_degraded')]
    )
    relationships = RailsMmd::RelationshipBuilder::DomainResult.new(
      domain_id: 'core',
      relationships: [
        relationship('relationships/users/account', 'entities/users', 'entities/accounts', 'account')
      ],
      diagnostics: [diagnostic('d_relationship_warning')]
    )
    relationships.relationships.first.metadata = { scoped: true }

    payload = described_class.new.build(domains: [domain], relationship_domains: [relationships]).domains.first.payload

    expect(payload.fetch('entities').map { |entity_payload| entity_payload.fetch('entity_id') }).to eq(
      %w[entities/accounts entities/users]
    )
    expect(payload.fetch('entities').last.fetch('attributes').map { |attribute| attribute.fetch('role') }).to eq(
      %w[primary_key foreign_key]
    )
    expect(payload.fetch('entities').last.fetch('attributes').map { |attribute| attribute.fetch('type') }).to eq(
      %w[integer integer]
    )
    expect(payload.fetch('relationships').first).to include(
      'relationship_id' => 'relationships/users/account',
      'association_name' => 'account',
      'owner_cardinality' => '0..many',
      'target_cardinality' => '1..1',
      'metadata' => { 'scoped' => true }
    )
    expect(payload.fetch('schema_version')).to eq(2)
    expect(JSON.generate(payload)).not_to include('safe_token', 'owner_foreign_key_column', 'target_primary_key_column')
    expect(payload.fetch('diagnostic_ids')).to eq(%w[d_db_metadata_degraded d_relationship_warning])
    expect(schema_valid_ir?(payload)).to be(true)
    expect(payload.fetch('digest_sha256')).to eq(
      RailsMmd::CanonicalJson.digest_sha256(payload.merge('digest_sha256' => nil))
    )
  end

  it 'supports attributes none without changing relationship serialization' do
    domain = RailsMmd::SchemaProbe::DomainResult.new(
      domain_id: 'core',
      entities: [entity('User', 'users', columns: [column('id'), column('account_id')])],
      diagnostics: []
    )
    result = described_class.new(attributes: :none).build(domains: [domain], relationship_domains: [])

    expect(result.domains.first.payload.fetch('entities').first.fetch('attributes')).to eq([])
    expect(schema_valid_ir?(result.domains.first.payload)).to be(true)
  end

  it 'marks a direct has foreign key on the actual target-side holder' do
    domain = RailsMmd::SchemaProbe::DomainResult.new(
      domain_id: 'core',
      entities: [entity('Author', 'authors'),
                 entity('Profile', 'profiles', columns: [column('id'), column('author_id')])],
      diagnostics: []
    )
    direct_has = relationship('relationships/authors/profile', 'entities/authors', 'entities/profiles', 'profile')
    direct_has.foreign_key_holder_entity_id = 'entities/profiles'
    direct_has.foreign_key_column = 'author_id'
    relationships = RailsMmd::RelationshipBuilder::DomainResult.new(
      domain_id: 'core', relationships: [direct_has], diagnostics: []
    )

    payload = described_class.new.build(domains: [domain], relationship_domains: [relationships]).domains.first.payload
    entities = payload.fetch('entities').to_h { |entity_payload| [entity_payload.fetch('entity_id'), entity_payload] }

    expect(entities.fetch('entities/authors').fetch('attributes').map do |attribute|
      attribute.fetch('name')
    end).to eq(['id'])
    expect(entities.fetch('entities/profiles').fetch('attributes').map { |attribute| attribute.fetch('name') }).to eq(
      %w[id author_id]
    )
  end

  it 'marks both polymorphic id and type columns as foreign keys' do
    domain = RailsMmd::SchemaProbe::DomainResult.new(
      domain_id: 'core',
      entities: [entity('Comment', 'comments',
                        columns: [column('id'), column('commentable_id'), column('commentable_type')]),
                 entity('Post', 'posts')],
      diagnostics: []
    )
    polymorphic = relationship(
      'relationships/comments/polymorphic/commentable/commentable_id/commentable_type/posts',
      'entities/comments', 'entities/posts', 'commentable'
    )
    polymorphic.foreign_key_holder_entity_id = 'entities/comments'
    polymorphic.foreign_key_column = 'commentable_id'
    polymorphic.foreign_type_column = 'commentable_type'
    relationships = RailsMmd::RelationshipBuilder::DomainResult.new(
      domain_id: 'core', relationships: [polymorphic], diagnostics: []
    )

    payload = described_class.new.build(domains: [domain], relationship_domains: [relationships]).domains.first.payload
    comment = payload.fetch('entities').find do |entity_payload|
      entity_payload.fetch('entity_id') == 'entities/comments'
    end

    expect(comment.fetch('attributes').map { |attribute| [attribute.fetch('name'), attribute.fetch('role')] }).to eq(
      [%w[id primary_key], %w[commentable_id foreign_key], %w[commentable_type foreign_key]]
    )
  end

  it 'does not project hidden HABTM join columns onto endpoint attributes' do
    domain = RailsMmd::SchemaProbe::DomainResult.new(
      domain_id: 'core', entities: [entity('Author', 'authors'), entity('Tag', 'tags')], diagnostics: []
    )
    habtm = relationship(
      'relationships/authors/habtm/authors_tags/author_id/tags/tag_id',
      'entities/authors', 'entities/tags', 'tags'
    )
    habtm.relationship_kind = :habtm
    habtm.owner_foreign_key_column = nil
    habtm.foreign_key_column = nil
    relationships = RailsMmd::RelationshipBuilder::DomainResult.new(
      domain_id: 'core', relationships: [habtm], diagnostics: []
    )

    payload = described_class.new.build(domains: [domain], relationship_domains: [relationships]).domains.first.payload

    expect(payload.fetch('entities').flat_map { |item| item.fetch('attributes') }.map { |item| item.fetch('role') })
      .to eq(%w[primary_key primary_key])
  end

  it 'falls back to unknown when selected key column type metadata is unavailable' do
    domain = RailsMmd::SchemaProbe::DomainResult.new(
      domain_id: 'core',
      entities: [
        entity('User', 'users', columns: [
                 RailsMmd::SchemaProbe::Column.new(name: 'id', type: nil, nullable: false)
               ])
      ],
      diagnostics: []
    )

    payload = described_class.new.build(domains: [domain], relationship_domains: []).domains.first.payload

    expect(payload.fetch('entities').first.fetch('attributes').first.fetch('type')).to eq('unknown')
    expect(schema_valid_ir?(payload)).to be(true)
  end

  def entity(ruby_constant, table_name, columns: [column('id')])
    RailsMmd::SchemaProbe::Entity.new(
      ruby_constant: ruby_constant,
      table_name: table_name,
      connection_context_id: '{"name":"primary"}',
      columns: columns,
      primary_key: 'id',
      foreign_keys: [],
      indexes: []
    )
  end

  def column(name)
    RailsMmd::SchemaProbe::Column.new(name: name, type: :integer, nullable: false)
  end

  def relationship(id, owner_id, target_id, name)
    RailsMmd::RelationshipBuilder::Relationship.new(
      relationship_id: id,
      owner_entity_id: owner_id,
      target_entity_id: target_id,
      association_name: name,
      owner_foreign_key_column: 'account_id',
      target_primary_key_column: 'id',
      owner_fk_unique: false,
      db_foreign_key: true,
      owner_fk_nullable: false,
      owner_cardinality: '0..many',
      target_cardinality: '1..1'
    )
  end

  def diagnostic(id)
    { 'diagnostic_id' => id }
  end

  def schema_valid_ir?(payload)
    RailsMmd::SchemaValidator.new.valid?(:ir, payload)
  end
end
# rubocop:enable Metrics/MethodLength, RSpec/ExampleLength, RSpec/MultipleExpectations
