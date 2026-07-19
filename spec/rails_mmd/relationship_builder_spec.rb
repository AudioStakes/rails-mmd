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
    expect(result.domains.first.relationships.map(&:relationship_id)).to eq(
      ['relationships/users/account_id/accounts/id']
    )
    relationship = result.domains.first.relationships.first
    expect(relationship.owner_entity_id).to eq('entities/users')
    expect(relationship.target_entity_id).to eq('entities/accounts')
    expect(relationship.association_name).to eq('account')
    expect(relationship.foreign_key_columns).to eq(['account_id'])
    expect(relationship.referenced_key_columns).to eq(['id'])
    expect(relationship.owner_fk_unique).to be(true)
    expect(relationship.db_foreign_key).to be(true)
    expect(relationship.owner_fk_nullable).to be(false)
    expect(relationship.owner_cardinality).to eq('0..1')
    expect(relationship.target_cardinality).to eq('1..1')
  end

  it 'omits a selected cross-context belongs-to before reading key bindings' do
    account_model = renderable_model('Account', 'accounts')
    reflection = belongs_to('account', klass: account_model)
    reflection.define_singleton_method(:foreign_key) { raise 'cross-context key reader must not run' }
    domain = domain_result(
      'core',
      [
        entity('Audit', 'audits', columns: [column('id', false), column('account_id', false)]),
        entity('Account', 'accounts', connection_context_id: '{"name":"archive"}')
      ]
    )

    result = build(domain, 'Audit' => owner_model(reflection), 'Account' => account_model)

    expect(result.domains.first.relationships).to eq([])
    expect(result.diagnostics).to contain_exactly(
      include(
        'code' => 'CONNECTION_RELATIONSHIP_OMITTED',
        'subject_id' => 'audits.account',
        'metadata' => include(
          'domain_id' => 'core', 'owner_constant' => 'Audit',
          'association_name' => 'account', 'target_constant' => 'Account'
        )
      )
    )
    expect(schema_valid_diagnostic?(result.diagnostics.first)).to be(true)
  end

  it 'omits direct has-one and has-many declarations across connection contexts' do
    profile = renderable_model('Profile', 'profiles')
    post = renderable_model('Post', 'posts')
    author = owner_model(
      association('profile', :has_one, klass: profile, foreign_key: 'author_id'),
      association('posts', :has_many, klass: post, foreign_key: 'author_id')
    )
    domain = domain_result(
      'core',
      [
        entity('Author', 'authors'),
        entity('Profile', 'profiles', columns: [column('id', false), column('author_id', false)],
                                      connection_context_id: '{"name":"archive"}'),
        entity('Post', 'posts', columns: [column('id', false), column('author_id', false)],
                                connection_context_id: '{"name":"archive"}')
      ]
    )

    result = build(domain, 'Author' => author, 'Profile' => profile, 'Post' => post)

    expect(result.domains.first.relationships).to eq([])
    expect(result.diagnostics.map { |diagnostic| diagnostic.fetch('code') }).to eq(
      %w[CONNECTION_RELATIONSHIP_OMITTED CONNECTION_RELATIONSHIP_OMITTED]
    )
    expect(result.diagnostics.map { |diagnostic| diagnostic.dig('metadata', 'association_name') })
      .to contain_exactly('profile', 'posts')
  end

  it 'publishes same-context siblings while omitting an independent cross-context edge' do
    account_model = renderable_model('Account', 'accounts')
    author_model = renderable_model('Author', 'authors')
    audit = owner_model(
      belongs_to('account', klass: account_model),
      belongs_to('author', klass: author_model)
    )
    domain = domain_result(
      'core',
      [
        entity('Audit', 'audits', columns: [column('id', false), column('account_id', false),
                                            column('author_id', false)]),
        entity('Account', 'accounts'),
        entity('Author', 'authors', connection_context_id: '{"name":"archive"}')
      ]
    )

    result = build(domain, 'Audit' => audit, 'Account' => account_model, 'Author' => author_model)

    expect(result.domains.first.relationships).to contain_exactly(
      have_attributes(association_name: 'account', target_entity_id: 'entities/accounts')
    )
    expect(result.diagnostics).to contain_exactly(
      include('code' => 'CONNECTION_RELATIONSHIP_OMITTED', 'subject_id' => 'audits.author')
    )
  end

  it 'publishes an ordered composite belongs-to tuple with exact tuple evidence' do
    account_model = renderable_model('Account', 'accounts')
    membership_model = owner_model(
      belongs_to(
        'account',
        klass: account_model,
        foreign_key: %w[tenant_id account_id],
        association_primary_key: %w[tenant_id id]
      )
    )
    domain = domain_result(
      'core',
      [
        entity(
          'Membership', 'memberships',
          columns: [column('id', false), column('tenant_id', false), column('account_id', false)],
          foreign_keys: [foreign_key('memberships', %w[tenant_id account_id], 'accounts', %w[tenant_id id])],
          indexes: [index(%w[account_id tenant_id], true, using: :btree)]
        ),
        entity(
          'Account', 'accounts',
          columns: [column('tenant_id', false), column('id', false)],
          primary_key_columns: %w[tenant_id id]
        )
      ]
    )

    result = build(domain, 'Membership' => membership_model, 'Account' => account_model)

    expect(result.diagnostics).to eq([])
    relationship = result.domains.first.relationships.fetch(0)
    expect(relationship).to have_attributes(
      relationship_id: 'relationships/memberships/tuple/WyJ0ZW5hbnRfaWQiLCJhY2NvdW50X2lkIl0/' \
                       'accounts/tuple/WyJ0ZW5hbnRfaWQiLCJpZCJd',
      foreign_key_holder_entity_id: 'entities/memberships',
      foreign_key_columns: %w[tenant_id account_id],
      referenced_key_columns: %w[tenant_id id],
      owner_fk_unique: true,
      db_foreign_key: true,
      owner_fk_nullable: false,
      owner_cardinality: '0..1',
      target_cardinality: '1..1'
    )
    expect(relationship).not_to respond_to(:foreign_key_column)
    expect(relationship.foreign_key_columns).to be_frozen
    expect(relationship.referenced_key_columns).to be_frozen
  end

  it 'retains scope presence on an eligible scoped belongs_to without executing it' do
    scope_executed = false
    user_model = owner_model(belongs_to('account', scope: -> { scope_executed = true }))
    domain = domain_result(
      'core',
      [
        entity('User', 'users', columns: [column('id', false), column('account_id', true)]),
        entity('Account', 'accounts', columns: [column('id', false)])
      ]
    )

    result = build(domain, 'User' => user_model, 'Account' => renderable_model('Account', 'accounts'))

    expect(result.diagnostics).to eq([])
    expect(result.domains.first.relationships.first).to have_attributes(
      association_name: 'account', metadata: { scoped: true }
    )
    expect(scope_executed).to be(false)
  end

  it 'merges reciprocal direct behavior under canonical owner and target directions' do
    user_model = renderable_model('User', 'users')
    account_model = renderable_model('Account', 'accounts')
    account = belongs_to(
      'account', klass: account_model, dependent: :delete, touch: :members_touched_at,
                 counter_cache: { active: true, column: nil }, counter_cache_column: 'members_count'
    )
    users = association(
      'users', :has_many, klass: user_model, foreign_key: 'account_id', dependent: :destroy
    )
    user_model.define_singleton_method(:reflect_on_all_associations) { |_macro = nil| [account] }
    account_model.define_singleton_method(:reflect_on_all_associations) { |_macro = nil| [users] }
    domain = domain_result(
      'core',
      [
        entity('User', 'users', columns: [column('id', false), column('account_id', true)]),
        entity('Account', 'accounts')
      ]
    )

    relationship = build(domain, 'User' => user_model, 'Account' => account_model)
                   .domains.first.relationships.fetch(0)

    expect(relationship.metadata).to eq(
      behavior: {
        from_owner: [
          {
            association_name: 'account', association_macro: 'belongs_to',
            dependent: { action: 'delete', target: 'associated_records' },
            touch: { attribute: 'members_touched_at' },
            counter_cache: { column: 'members_count', active: true }
          }
        ],
        from_target: [
          {
            association_name: 'users', association_macro: 'has_many',
            dependent: { action: 'destroy', target: 'associated_records' }
          }
        ]
      }
    )
  end

  it 'keeps an eligible edge when behavior options are unreadable' do
    account_model = renderable_model('Account', 'accounts')
    account = belongs_to('account', klass: account_model)
    account.define_singleton_method(:options) { raise 'unreadable behavior options' }
    user_model = owner_model(account)
    domain = domain_result(
      'core',
      [
        entity('User', 'users', columns: [column('id', false), column('account_id', true)]),
        entity('Account', 'accounts')
      ]
    )

    result = build(domain, 'User' => user_model, 'Account' => account_model)

    expect(result.domains.first.relationships).to contain_exactly(have_attributes(metadata: nil))
    expect(result.diagnostics).to eq([])
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
      ['ASSOCIATION_TARGET_UNRESOLVED']
    )
  end

  it 'resolves every supported macro before target eligibility' do
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
      ['authors.profile', 'ASSOCIATION_TARGET_UNRESOLVED', nil],
      ['authors.posts', 'ASSOCIATION_TARGET_UNRESOLVED', nil],
      ['authors.tags', 'ASSOCIATION_TARGET_UNRESOLVED', nil]
    )
    expect(result.diagnostics).to all(satisfy { |diagnostic| schema_valid_diagnostic?(diagnostic) })
  end

  it 'builds one validated HABTM many-to-many edge without endpoint FK columns' do
    tag_model = renderable_model('Tag', 'tags')
    tags = association(
      'tags', :has_and_belongs_to_many, klass: tag_model, join_table: 'authors_tags',
                                        foreign_key: 'author_id', association_foreign_key: 'tag_id'
    )
    domain = domain_result(
      'core', [entity('Author', 'authors'), entity('Tag', 'tags')],
      join_tables: [join_table('authors_tags', %w[author_id tag_id])]
    )

    result = build(domain, 'Author' => owner_model(tags), 'Tag' => owner_model)

    expect(result.diagnostics).to eq([])
    expect(result.domains.first.relationships).to contain_exactly(
      have_attributes(
        relationship_id: 'relationships/authors/habtm/authors_tags/author_id/tags/tag_id',
        owner_entity_id: 'entities/authors', target_entity_id: 'entities/tags',
        association_name: 'tags', relationship_kind: :habtm,
        owner_cardinality: '0..many', target_cardinality: '0..many',
        foreign_key_holder_entity_id: nil, foreign_key_columns: nil
      )
    )
  end

  it 'omits cross-context HABTM before reading hidden join-table keys' do
    tag_model = renderable_model('Tag', 'tags')
    tags = association(
      'tags', :has_and_belongs_to_many, klass: tag_model, join_table: 'authors_tags',
                                        foreign_key: 'author_id', association_foreign_key: 'tag_id'
    )
    tags.define_singleton_method(:join_table) { raise 'cross-context join reader must not run' }
    domain = domain_result(
      'core',
      [entity('Author', 'authors'), entity('Tag', 'tags', connection_context_id: '{"name":"archive"}')]
    )

    result = build(domain, 'Author' => owner_model(tags), 'Tag' => tag_model)

    expect(result.domains.first.relationships).to eq([])
    expect(result.diagnostics).to contain_exactly(
      include('code' => 'CONNECTION_RELATIONSHIP_OMITTED', 'subject_id' => 'authors.tags')
    )
  end

  it 'selects same-named hidden HABTM tables by connection context and local name' do
    tag_model = renderable_model('Tag', 'tags')
    role_model = renderable_model('Role', 'roles')
    tags = association(
      'tags', :has_and_belongs_to_many, klass: tag_model, join_table: 'memberships',
                                        foreign_key: 'author_id', association_foreign_key: 'tag_id'
    )
    roles = association(
      'roles', :has_and_belongs_to_many, klass: role_model, join_table: 'memberships',
                                         foreign_key: 'admin_id', association_foreign_key: 'role_id'
    )
    archive_context = '{"name":"archive"}'
    domain = domain_result(
      'core',
      [
        entity('Author', 'authors'), entity('Tag', 'tags'),
        entity('Admin', 'admins', connection_context_id: archive_context),
        entity('Role', 'roles', connection_context_id: archive_context)
      ],
      join_tables: [
        join_table('memberships', %w[author_id tag_id]),
        join_table('memberships', %w[admin_id role_id], connection_context_id: archive_context)
      ]
    )

    result = build(
      domain,
      'Author' => owner_model(tags), 'Tag' => tag_model,
      'Admin' => owner_model(roles), 'Role' => role_model
    )

    expect(result.diagnostics).to eq([])
    expect(result.domains.first.relationships.map(&:association_name)).to contain_exactly('tags', 'roles')
  end

  it 'deduplicates reciprocal HABTM declarations with left-owner label priority' do
    author_model = renderable_model('Author', 'authors')
    tag_model = renderable_model('Tag', 'tags')
    author_tags = association(
      'tags', :has_and_belongs_to_many, klass: tag_model, join_table: 'authors_tags',
                                        foreign_key: 'author_id', association_foreign_key: 'tag_id'
    )
    tag_authors = association(
      'authors', :has_and_belongs_to_many, klass: author_model, join_table: 'authors_tags',
                                           foreign_key: 'tag_id', association_foreign_key: 'author_id'
    )
    domain = domain_result(
      'core', [entity('Tag', 'tags'), entity('Author', 'authors')],
      join_tables: [join_table('authors_tags', %w[tag_id author_id])]
    )

    result = build(domain, 'Tag' => owner_model(tag_authors), 'Author' => owner_model(author_tags))

    expect(result.diagnostics).to eq([])
    expect(result.domains.first.relationships).to contain_exactly(
      have_attributes(
        relationship_id: 'relationships/authors/habtm/authors_tags/author_id/tags/tag_id',
        owner_entity_id: 'entities/authors', target_entity_id: 'entities/tags', association_name: 'tags'
      )
    )
  end

  it 'builds custom-key self-HABTM with a stable column-normalized identity' do
    author_model = renderable_model('Author', 'authors')
    coauthors = association(
      'coauthors', :has_and_belongs_to_many, klass: author_model, join_table: 'author_links',
                                             foreign_key: 'author_id',
                                             association_foreign_key: 'coauthor_id'
    )
    domain = domain_result(
      'core', [entity('Author', 'authors')],
      join_tables: [join_table('author_links', %w[coauthor_id author_id])]
    )

    relationship = build(domain, 'Author' => owner_model(coauthors)).domains.first.relationships.first

    expect(relationship).to have_attributes(
      relationship_id: 'relationships/authors/habtm/author_links/author_id/authors/coauthor_id',
      owner_entity_id: 'entities/authors', target_entity_id: 'entities/authors', association_name: 'coauthors'
    )
  end

  it 'diagnoses invalid HABTM join-table shapes with a closed reason' do
    tag_model = renderable_model('Tag', 'tags')
    tags = association(
      'tags', :has_and_belongs_to_many, klass: tag_model, join_table: 'authors_tags',
                                        foreign_key: 'author_id', association_foreign_key: 'tag_id'
    )
    domain = domain_result('core', [entity('Author', 'authors'), entity('Tag', 'tags')])

    result = build(domain, 'Author' => owner_model(tags), 'Tag' => owner_model)

    expect(result.domains.first.relationships).to eq([])
    expect(result.diagnostics).to contain_exactly(
      include(
        'code' => 'ASSOCIATION_JOIN_TABLE_INVALID',
        'metadata' => include('join_table' => 'authors_tags', 'reason' => 'unresolved')
      )
    )
  end

  it 'classifies every invalid HABTM table-global shape deterministically' do
    tag_model = renderable_model('Tag', 'tags')
    cases = {
      'primary_key_present' => [
        join_table('authors_tags', %w[author_id tag_id], primary_key_columns: ['id']), 'tag_id'
      ],
      'join_column_missing' => [join_table('authors_tags', ['author_id']), 'tag_id'],
      'extra_columns' => [join_table('authors_tags', %w[author_id tag_id created_at]), 'tag_id'],
      'ambiguous_columns' => [join_table('authors_tags', ['author_id']), 'author_id']
    }

    actual = cases.map do |_expected_reason, (table, target_column)|
      reflection = association(
        'tags', :has_and_belongs_to_many, klass: tag_model, join_table: 'authors_tags',
                                          foreign_key: 'author_id', association_foreign_key: target_column
      )
      domain = domain_result(
        'core', [entity('Author', 'authors'), entity('Tag', 'tags')], join_tables: [table]
      )
      diagnostic = build(domain, 'Author' => owner_model(reflection), 'Tag' => owner_model).diagnostics.fetch(0)
      [diagnostic.fetch('code'), diagnostic.dig('metadata', 'reason'), schema_valid_diagnostic?(diagnostic)]
    end

    expect(actual).to eq(cases.keys.map { |reason| ['ASSOCIATION_JOIN_TABLE_INVALID', reason, true] })
  end

  it 'merges a scoped same-signature HABTM alias without executing its scope' do
    tag_model = renderable_model('Tag', 'tags')
    valid = association(
      'tags', :has_and_belongs_to_many, klass: tag_model, join_table: 'authors_tags',
                                        foreign_key: 'author_id', association_foreign_key: 'tag_id'
    )
    scoped = association(
      'recent_tags', :has_and_belongs_to_many, klass: tag_model, join_table: 'authors_tags',
                                               scope: -> { raise 'scope executed' },
                                               dependent: :destroy, touch: true,
                                               counter_cache: { active: true, column: 'authors_count' },
                                               foreign_key: 'author_id', association_foreign_key: 'tag_id'
    )
    domain = domain_result(
      'core', [entity('Author', 'authors'), entity('Tag', 'tags')],
      join_tables: [join_table('authors_tags', %w[author_id tag_id])]
    )

    result = build(domain, 'Author' => owner_model(scoped, valid), 'Tag' => owner_model)

    expect(result.domains.first.relationships).to contain_exactly(
      have_attributes(association_name: 'recent_tags', metadata: { scoped: true })
    )
    expect(result.diagnostics).to eq([])
  end

  it 'omits a HABTM target that resolves but is not renderable' do
    hidden_tag = renderable_model('Tag', 'tags', renderable: false)
    reflection = association(
      'tags', :has_and_belongs_to_many, klass: hidden_tag, join_table: 'authors_tags',
                                        foreign_key: 'author_id', association_foreign_key: 'tag_id'
    )
    domain = domain_result(
      'core', [entity('Author', 'authors'), entity('Tag', 'tags')],
      join_tables: [join_table('authors_tags', %w[author_id tag_id])]
    )

    result = build(domain, 'Author' => owner_model(reflection), 'Tag' => owner_model)

    expect(result.domains.first.relationships).to eq([])
    expect(result.diagnostics.first).to include('code' => 'ASSOCIATION_TARGET_NOT_RENDERABLE_OMITTED')
  end

  it 'builds inverse-free direct has relationships from target-side FK evidence' do
    author = owner_model(
      association('profiles', :has_many, klass: renderable_model('Profile', 'profiles'),
                                         scope: -> { raise 'scope executed' }, foreign_key: 'author_id'),
      association('account', :has_one, klass: renderable_model('Account', 'accounts'),
                                       scope: -> { raise 'scope executed' }, foreign_key: 'author_id')
    )
    domain = domain_result(
      'core',
      [
        entity('Author', 'authors'),
        entity('Profile', 'profiles', columns: [column('id', false), column('author_id', true)]),
        entity('Account', 'accounts', columns: [column('id', false), column('author_id', false)],
                                      foreign_keys: [foreign_key('accounts', 'author_id', 'authors', 'id')],
                                      indexes: [index(['author_id'], true, using: :btree)])
      ]
    )

    result = build(domain, 'Author' => author)
    relationships = result.domains.first.relationships.to_h do |relationship|
      [relationship.association_name, relationship]
    end

    expect(result.diagnostics).to eq([])
    expect(relationships.fetch('profiles')).to have_attributes(
      relationship_id: 'relationships/profiles/author_id/authors/id',
      owner_entity_id: 'entities/profiles', target_entity_id: 'entities/authors',
      foreign_key_holder_entity_id: 'entities/profiles', foreign_key_columns: ['author_id'],
      owner_cardinality: '0..many', target_cardinality: '0..1', metadata: { scoped: true }
    )
    expect(relationships.fetch('account')).to have_attributes(
      relationship_id: 'relationships/accounts/author_id/authors/id',
      owner_entity_id: 'entities/accounts', target_entity_id: 'entities/authors',
      foreign_key_holder_entity_id: 'entities/accounts', foreign_key_columns: ['author_id'],
      owner_cardinality: '0..1', target_cardinality: '1..1', metadata: { scoped: true }
    )
  end

  it 'publishes direct has-many query-constraint tuples from the target-side holder' do
    invoice_model = renderable_model('Invoice', 'invoices')
    account_model = owner_model(
      association(
        'invoices', :has_many,
        klass: invoice_model,
        foreign_key: %w[account_tenant_id account_id],
        active_record_primary_key: %w[tenant_id id]
      )
    )
    domain = domain_result(
      'core',
      [
        entity(
          'Account', 'accounts',
          columns: [column('tenant_id', false), column('id', false)],
          primary_key_columns: %w[tenant_id id]
        ),
        entity(
          'Invoice', 'invoices',
          columns: [column('id', false), column('account_tenant_id', false), column('account_id', false)],
          foreign_keys: [
            foreign_key('invoices', %w[account_tenant_id account_id], 'accounts', %w[tenant_id id])
          ]
        )
      ]
    )

    result = build(domain, 'Account' => account_model)

    expect(result.diagnostics).to eq([])
    expect(result.domains.first.relationships).to contain_exactly(
      have_attributes(
        relationship_id: 'relationships/invoices/tuple/' \
                         'WyJhY2NvdW50X3RlbmFudF9pZCIsImFjY291bnRfaWQiXQ/' \
                         'accounts/tuple/WyJ0ZW5hbnRfaWQiLCJpZCJd',
        foreign_key_holder_entity_id: 'entities/invoices',
        foreign_key_columns: %w[account_tenant_id account_id],
        referenced_key_columns: %w[tenant_id id],
        owner_cardinality: '0..many',
        target_cardinality: '1..1'
      )
    )
  end

  it 'keeps unsupported direct-has variants on deterministic omission paths' do
    author = owner_model(
      association('groups', :has_many, through: true),
      association('recent_posts', :has_many, scope: -> {}),
      association('assets', :has_many, type: 'attachable_type')
    )
    domain = domain_result('core', [entity('Author', 'authors')])

    result = build(domain, 'Author' => author)

    expect(result.domains.first.relationships).to eq([])
    expect(result.diagnostics.map { |diagnostic| diagnostic.fetch('code') }).to eq(
      %w[ASSOCIATION_THROUGH_UNRESOLVED ASSOCIATION_TARGET_UNRESOLVED ASSOCIATION_TARGET_UNRESOLVED]
    )
  end

  it 'classifies a rootless inverse with an unselected holder as a domain boundary' do
    inverse = association(
      'comments', :has_many, klass: renderable_model('Comment', 'comments'), as: :commentable,
                             scope: -> {}, foreign_key: 'commentable_id', type: 'commentable_type'
    )
    domain = domain_result('core', [entity('Post', 'posts')])

    result = build(domain, 'Post' => owner_model(inverse))

    expect(result.domains.first.relationships).to eq([])
    expect(result.diagnostics.map { |diagnostic| diagnostic.fetch('code') }).to eq(
      ['DOMAIN_RELATIONSHIP_OMITTED']
    )
  end

  it 'contains an unsupported rootless polymorphic inverse name' do
    inverse = association(
      'BadName', :has_many, klass: renderable_model('Comment', 'comments'), as: :commentable,
                            foreign_key: 'commentable_id', type: 'commentable_type'
    )
    domain = domain_result('core', [entity('Post', 'posts'), entity('Comment', 'comments')])

    result = build(domain, 'Post' => owner_model(inverse))

    expect(result.domains.first.relationships).to eq([])
    expect(result.diagnostics.map { |diagnostic| diagnostic.fetch('code') }).to eq(
      ['ASSOCIATION_NAME_UNSUPPORTED_OMITTED']
    )
  end

  it 'keeps the generic rootless inverse fallback when its target reader fails' do
    inverse = association(
      'comments', :has_many, klass: -> { raise 'target unavailable' }, as: :commentable,
                             foreign_key: 'commentable_id', type: 'commentable_type'
    )
    domain = domain_result('core', [entity('Post', 'posts')])

    result = build(domain, 'Post' => owner_model(inverse))

    expect(result.domains.first.relationships).to eq([])
    expect(result.diagnostics.map { |diagnostic| diagnostic.fetch('code') }).to eq(
      ['ASSOCIATION_POLYMORPHIC_OMITTED']
    )
  end

  it 'builds one polymorphic edge per matching inverse candidate' do
    comment_model = renderable_model('Comment', 'comments')
    renderable_model('Post', 'posts')
    renderable_model('Image', 'images')
    commentable = belongs_to('commentable', polymorphic: true, scope: -> { raise 'scope executed' })
    post_comments = association(
      'comments', :has_many, klass: comment_model, as: :commentable,
                             foreign_key: 'commentable_id', type: 'commentable_type'
    )
    image_comment = association(
      'comment', :has_one, klass: comment_model, as: :commentable,
                           foreign_key: 'commentable_id', type: 'commentable_type'
    )
    domain = domain_result(
      'core',
      [entity('Comment', 'comments', columns: [column('id', false), column('commentable_id', false),
                                               column('commentable_type', false)]),
       entity('Post', 'posts'), entity('Image', 'images')]
    )

    result = build(
      domain,
      'Comment' => owner_model(commentable),
      'Post' => owner_model(post_comments),
      'Image' => owner_model(image_comment)
    )
    polymorphic = result.domains.first.relationships.select do |relationship|
      relationship.relationship_kind == :polymorphic
    end

    expect(result.diagnostics).to eq([])
    expect(polymorphic).to contain_exactly(
      have_attributes(
        relationship_id: 'relationships/comments/polymorphic/commentable/commentable_id/commentable_type/posts',
        owner_entity_id: 'entities/comments', target_entity_id: 'entities/posts',
        association_name: 'commentable', foreign_key_columns: ['commentable_id'],
        foreign_type_column: 'commentable_type', owner_cardinality: '0..many', target_cardinality: '0..1',
        metadata: { scoped: true }
      ),
      have_attributes(
        relationship_id: 'relationships/comments/polymorphic/commentable/commentable_id/commentable_type/images',
        owner_entity_id: 'entities/comments', target_entity_id: 'entities/images',
        association_name: 'commentable', foreign_key_columns: ['commentable_id'],
        foreign_type_column: 'commentable_type', owner_cardinality: '0..many', target_cardinality: '0..1',
        metadata: { scoped: true }
      )
    )
  end

  it 'classifies an unhandled inverse whose selected holder is on another context' do
    comment_model = renderable_model('Comment', 'comments')
    inverse = association(
      'comments', :has_many, klass: comment_model, as: :commentable,
                             foreign_key: 'commentable_id', type: 'commentable_type'
    )
    domain = domain_result(
      'core',
      [
        entity('Post', 'posts', connection_context_id: '{"name":"archive"}'),
        entity('Comment', 'comments', columns: [column('id', false), column('commentable_id', false),
                                                column('commentable_type', false)])
      ]
    )

    result = build(domain, 'Post' => owner_model(inverse), 'Comment' => comment_model)

    expect(result.domains.first.relationships).to eq([])
    expect(result.diagnostics).to contain_exactly(
      include(
        'code' => 'CONNECTION_RELATIONSHIP_OMITTED',
        'subject_id' => 'posts.comments',
        'metadata' => include('target_constant' => 'Comment')
      )
    )
  end

  it 'keeps same-context polymorphic candidates and diagnoses each rejected concrete target' do
    comment_model = renderable_model('Comment', 'comments')
    root = belongs_to('commentable', polymorphic: true)
    inverse = lambda do |name|
      association(name, :has_many, klass: comment_model, as: :commentable,
                                   foreign_key: 'commentable_id', type: 'commentable_type')
    end
    domain = domain_result(
      'core',
      [
        entity('Comment', 'comments', columns: [column('id', false), column('commentable_id', false),
                                                column('commentable_type', false)]),
        entity('Post', 'posts'),
        entity('Image', 'images', connection_context_id: '{"name":"archive"}'),
        entity('Video', 'videos', connection_context_id: '{"name":"archive"}')
      ]
    )

    result = build(
      domain,
      'Comment' => owner_model(root),
      'Post' => owner_model(inverse.call('comments')),
      'Image' => owner_model(inverse.call('comments')),
      'Video' => owner_model(inverse.call('comments'))
    )

    polymorphic = result.domains.first.relationships.select do |relationship|
      relationship.relationship_kind == :polymorphic
    end
    expect(polymorphic).to contain_exactly(have_attributes(target_entity_id: 'entities/posts'))
    expect(result.diagnostics.map { |diagnostic| diagnostic.fetch('code') }).to eq(
      %w[CONNECTION_RELATIONSHIP_OMITTED CONNECTION_RELATIONSHIP_OMITTED]
    )
    expect(result.diagnostics.map { |diagnostic| diagnostic.dig('metadata', 'target_constant') })
      .to contain_exactly('Image', 'Video')
  end

  it 'publishes a composite polymorphic identifier against a concrete target tuple' do
    comment_model = renderable_model('Comment', 'comments')
    post_model = owner_model(
      association(
        'comments', :has_many,
        klass: comment_model,
        as: :commentable,
        foreign_key: %w[tenant_id commentable_id],
        type: 'commentable_type',
        active_record_primary_key: %w[tenant_id id]
      )
    )
    root = belongs_to(
      'commentable',
      polymorphic: true,
      foreign_key: %w[tenant_id commentable_id],
      association_primary_key: %w[tenant_id id]
    )
    domain = domain_result(
      'core',
      [
        entity(
          'Comment', 'comments',
          columns: [column('id', false), column('tenant_id', false), column('commentable_id', false),
                    column('commentable_type', false)],
          indexes: [index(%w[commentable_type commentable_id tenant_id], true)]
        ),
        entity(
          'Post', 'posts',
          columns: [column('tenant_id', false), column('id', false)],
          primary_key_columns: %w[tenant_id id]
        )
      ]
    )

    result = build(domain, 'Comment' => owner_model(root), 'Post' => post_model)

    expect(result.diagnostics).to eq([])
    expect(result.domains.first.relationships).to contain_exactly(
      have_attributes(
        relationship_id: 'relationships/comments/polymorphic/commentable/tuple/' \
                         'WyJ0ZW5hbnRfaWQiLCJjb21tZW50YWJsZV9pZCJd/commentable_type/posts',
        foreign_key_columns: %w[tenant_id commentable_id],
        foreign_type_column: 'commentable_type',
        referenced_key_columns: %w[tenant_id id],
        owner_cardinality: '0..1',
        target_cardinality: '0..1'
      )
    )
  end

  it 'deduplicates same-target polymorphic inverses with singular and lexical priority' do
    comment_model = renderable_model('Comment', 'comments')
    root = belongs_to('commentable', polymorphic: true)
    many = association('comments', :has_many, klass: comment_model, as: :commentable,
                                              foreign_key: 'commentable_id', type: 'commentable_type',
                                              scope: -> { raise 'scope executed' })
    singular_alias = association('featured_comment', :has_one, klass: comment_model, as: :commentable,
                                                               foreign_key: 'commentable_id', type: 'commentable_type')
    domain = domain_result(
      'core',
      [entity('Comment', 'comments', columns: [column('id', false), column('commentable_id', false),
                                               column('commentable_type', false)]),
       entity('Post', 'posts')]
    )

    results = [owner_model(many, singular_alias), owner_model(singular_alias, many)].map do |post|
      build(domain, 'Comment' => owner_model(root), 'Post' => post)
    end
    polymorphic = results.map do |result|
      result.domains.first.relationships.find { |relationship| relationship.relationship_kind == :polymorphic }
    end

    expect(results.flat_map(&:diagnostics)).to eq([])
    expect(polymorphic).to all(have_attributes(owner_cardinality: '0..many', metadata: { scoped: true }))
  end

  it 'merges scope metadata across duplicate polymorphic roots in either declaration order' do
    comment_model = renderable_model('Comment', 'comments')
    plain_root = belongs_to('commentable', polymorphic: true)
    scoped_root = belongs_to('commentable', polymorphic: true, scope: -> { raise 'scope executed' })
    inverse = association('comments', :has_many, klass: comment_model, as: :commentable,
                                                 foreign_key: 'commentable_id', type: 'commentable_type')
    domain = domain_result(
      'core',
      [entity('Comment', 'comments', columns: [column('id', false), column('commentable_id', false),
                                               column('commentable_type', false)]),
       entity('Post', 'posts')]
    )

    relationships = [[plain_root, scoped_root], [scoped_root, plain_root]].map do |roots|
      build(domain, 'Comment' => owner_model(*roots), 'Post' => owner_model(inverse))
        .domains.first.relationships
    end

    expect(relationships).to all(contain_exactly(have_attributes(metadata: { scoped: true })))
  end

  it 'merges polymorphic root and concrete inverse behavior without flattening direction' do
    comment_model = renderable_model('Comment', 'comments')
    root = belongs_to(
      'commentable', polymorphic: true, dependent: :destroy, touch: true,
                     counter_cache: { active: true, column: 'comments_count' },
                     counter_cache_column: 'comments_count'
    )
    inverse = association(
      'comments', :has_many, klass: comment_model, as: :commentable,
                             foreign_key: 'commentable_id', type: 'commentable_type',
                             dependent: :nullify
    )
    domain = domain_result(
      'core',
      [
        entity(
          'Comment', 'comments',
          columns: [column('id', false), column('commentable_id', false), column('commentable_type', false)]
        ),
        entity('Post', 'posts')
      ]
    )

    relationship = build(domain, 'Comment' => owner_model(root), 'Post' => owner_model(inverse))
                   .domains.first.relationships.fetch(0)

    expect(relationship.metadata).to eq(
      behavior: {
        from_owner: [
          {
            association_name: 'commentable', association_macro: 'belongs_to',
            dependent: { action: 'destroy', target: 'associated_records' },
            touch: { attribute: nil },
            counter_cache: { column: 'comments_count', active: true }
          }
        ],
        from_target: [
          {
            association_name: 'comments', association_macro: 'has_many',
            dependent: { action: 'nullify', target: 'associated_records' }
          }
        ]
      }
    )
  end

  it 'publishes valid polymorphic candidates while diagnosing conflicting inverses' do
    comment_model = renderable_model('Comment', 'comments')
    root = belongs_to('commentable', polymorphic: true)
    valid = association('comments', :has_many, klass: comment_model, as: :commentable,
                                               foreign_key: 'commentable_id', type: 'commentable_type')
    conflicting = association('comment', :has_one, klass: comment_model, as: :commentable,
                                                   foreign_key: 'commentable_id', type: 'wrong_type')
    domain = domain_result(
      'core',
      [entity('Comment', 'comments', columns: [column('id', false), column('commentable_id', false),
                                               column('commentable_type', false)]),
       entity('Post', 'posts'), entity('Image', 'images')]
    )

    result = build(
      domain,
      'Comment' => owner_model(root),
      'Post' => owner_model(valid),
      'Image' => owner_model(conflicting)
    )

    expect(result.domains.first.relationships.map(&:target_entity_id)).to eq(['entities/posts'])
    expect(result.diagnostics.map { |diagnostic| diagnostic.fetch('code') }).to eq(
      ['ASSOCIATION_POLYMORPHIC_OMITTED']
    )
  end

  it 'diagnoses polymorphic roots with zero candidates or an incomplete key pair' do
    root = belongs_to('commentable', polymorphic: true)
    complete = domain_result(
      'core', [entity('Comment', 'comments', columns: [column('id', false), column('commentable_id', false),
                                                       column('commentable_type', false)])]
    )
    incomplete = domain_result(
      'core', [entity('Comment', 'comments', columns: [column('id', false), column('commentable_id', false)])]
    )

    zero_candidates = build(complete, 'Comment' => owner_model(root))
    missing_column = build(incomplete, 'Comment' => owner_model(root))
    unreadable_root = build(
      complete,
      'Comment' => owner_model(
        belongs_to('commentable', polymorphic: true, foreign_key: -> { raise 'unreadable root key' })
      )
    )

    expect(zero_candidates.diagnostics.map { |diagnostic| diagnostic.fetch('code') }).to eq(
      ['ASSOCIATION_POLYMORPHIC_TARGETS_UNRESOLVED']
    )
    expect(missing_column.diagnostics.map { |diagnostic| diagnostic.fetch('code') }).to eq(
      ['ASSOCIATION_KEY_COLUMN_MISSING']
    )
    expect(unreadable_root.diagnostics.map { |diagnostic| diagnostic.fetch('code') }).to eq(
      ['ASSOCIATION_COMPOSITE_KEY_OMITTED']
    )
  end

  it 'diagnoses unsafe names and missing composite polymorphic holder columns without resolving a target class' do
    domain = domain_result('core', [entity('Comment', 'comments')])

    unsafe = build(domain, 'Comment' => owner_model(belongs_to('BadName', polymorphic: true)))
    composite = build(
      domain,
      'Comment' => owner_model(belongs_to('commentable', polymorphic: true,
                                                         foreign_key: %w[commentable_id tenant_id]))
    )

    expect(unsafe.diagnostics.map { |diagnostic| diagnostic.fetch('code') }).to eq(
      ['ASSOCIATION_NAME_UNSUPPORTED_OMITTED']
    )
    expect(composite.diagnostics.map { |diagnostic| diagnostic.fetch('code') }).to eq(
      ['ASSOCIATION_KEY_COLUMN_MISSING']
    )
  end

  it 'publishes custom scalar polymorphic key names' do
    comment_model = renderable_model('Comment', 'comments')
    root = belongs_to('commentable', polymorphic: true, foreign_key: 'subject_id',
                                     foreign_type: 'subject_kind', association_primary_key: 'slug')
    inverse = association('comments', :has_many, klass: comment_model, as: :commentable,
                                                 foreign_key: 'subject_id', type: 'subject_kind',
                                                 active_record_primary_key: 'slug', primary_key: 'slug')
    domain = domain_result(
      'core',
      [
        entity('Comment', 'comments', columns: [column('id', false), column('subject_id', false),
                                                column('subject_kind', false)]),
        entity('Post', 'posts', columns: [column('id', false), column('slug', false)])
      ]
    )

    result = build(domain, 'Comment' => owner_model(root), 'Post' => owner_model(inverse))

    expect(result.diagnostics).to eq([])
    expect(result.domains.first.relationships).to contain_exactly(
      have_attributes(
        relationship_id: 'relationships/comments/polymorphic/commentable/subject_id/subject_kind/posts',
        foreign_key_columns: ['subject_id'],
        foreign_type_column: 'subject_kind',
        referenced_key_columns: ['slug']
      )
    )
  end

  it 'retains a local target diagnostic for an unresolved ordinary polymorphic inverse' do
    root = belongs_to('commentable', polymorphic: true)
    unresolved_inverse = association(
      'comments', :has_many, class_name: 'MissingComment', as: :commentable,
                             foreign_key: 'commentable_id', type: 'commentable_type'
    )
    domain = domain_result(
      'core',
      [
        entity('Comment', 'comments', columns: [column('id', false), column('commentable_id', false),
                                                column('commentable_type', false)]),
        entity('Post', 'posts')
      ]
    )

    result = build(domain, 'Comment' => owner_model(root), 'Post' => owner_model(unresolved_inverse))

    expect(result.diagnostics.map { |diagnostic| diagnostic.fetch('code') }).to eq(
      %w[ASSOCIATION_TARGET_UNRESOLVED ASSOCIATION_POLYMORPHIC_TARGETS_UNRESOLVED]
    )
    expect(result.diagnostics.first.fetch('subject_id')).to eq('posts.comments')
  end

  it 'publishes a scoped polymorphic candidate beside independent structural diagnostics' do
    comment_model = renderable_model('Comment', 'comments')
    root = belongs_to('commentable', polymorphic: true)
    scoped = association('comments', :has_many, klass: comment_model, as: :commentable, scope: -> {},
                                                foreign_key: 'commentable_id', type: 'commentable_type')
    wrong_primary = association('comments', :has_many, klass: comment_model, as: :commentable,
                                                       foreign_key: 'commentable_id', type: 'commentable_type',
                                                       active_record_primary_key: 'uuid')
    missing_primary = association('comment', :has_one, klass: comment_model, as: :commentable,
                                                       foreign_key: 'commentable_id', type: 'commentable_type',
                                                       active_record_primary_key: 'uuid')
    non_renderable = association(
      'comments', :has_many, klass: renderable_model('Comment', 'comments', renderable: false), as: :commentable,
                             foreign_key: 'commentable_id', type: 'commentable_type'
    )
    domain = domain_result(
      'core',
      [entity('Comment', 'comments', columns: [column('id', false), column('commentable_id', false),
                                               column('commentable_type', false)]),
       entity('Post', 'posts'), entity('Image', 'images', columns: [column('id', false), column('uuid', false)]),
       entity('Video', 'videos', primary_key_columns: ['uuid']), entity('Audio', 'audios')]
    )

    result = build(
      domain,
      'Comment' => owner_model(root), 'Post' => owner_model(scoped),
      'Image' => owner_model(wrong_primary), 'Video' => owner_model(missing_primary),
      'Audio' => owner_model(non_renderable)
    )

    expect(result.domains.first.relationships).to contain_exactly(
      have_attributes(target_entity_id: 'entities/posts', metadata: { scoped: true })
    )
    expect(result.diagnostics.map { |diagnostic| diagnostic.fetch('code') }).to contain_exactly(
      'ASSOCIATION_POLYMORPHIC_OMITTED',
      'ASSOCIATION_KEY_COLUMN_MISSING',
      'ASSOCIATION_TARGET_NOT_RENDERABLE_OMITTED'
    )
  end

  it 'contains unreadable inverse options and strengthens an exact unique polymorphic key pair' do
    comment_model = renderable_model('Comment', 'comments')
    root = belongs_to('commentable', polymorphic: true)
    valid = association('comments', :has_many, klass: comment_model, as: :commentable,
                                               foreign_key: 'commentable_id', type: 'commentable_type')
    unreadable = unreadable_polymorphic_inverse(comment_model)
    domain = domain_result(
      'core',
      [entity('Comment', 'comments', columns: [column('id', false), column('commentable_id', false),
                                               column('commentable_type', false)],
                                     indexes: [index(%w[commentable_type commentable_id], true)]),
       entity('Post', 'posts'), entity('Image', 'images')]
    )

    result = build(
      domain,
      'Comment' => owner_model(root), 'Post' => owner_model(valid), 'Image' => owner_model(unreadable)
    )

    expect(result.domains.first.relationships).to contain_exactly(have_attributes(owner_cardinality: '0..1'))
    expect(result.diagnostics.map { |diagnostic| diagnostic.fetch('code') }).to eq(
      ['ASSOCIATION_POLYMORPHIC_OMITTED']
    )
  end

  it 'publishes delegated whitelist targets without inverse discovery authority' do
    entry_model = renderable_model('Entry', 'entries')
    image_inverse = association(
      'entry', :has_one, klass: entry_model, as: :entryable,
                         foreign_key: 'entryable_id', type: 'entryable_type',
                         dependent: :nullify,
                         scope: -> { raise 'scope executed' }
    )
    undeclared_inverse = association(
      'entries',
      :has_many,
      klass: entry_model,
      as: :entryable,
      foreign_key: 'entryable_id',
      type: 'entryable_type'
    )
    domain = domain_result(
      'core',
      [entity('Entry', 'entries', columns: [column('id', false), column('entryable_id', false),
                                            column('entryable_type', false)]),
       entity('Post', 'posts'),
       entity('Image', 'images'),
       entity('Video', 'videos')],
      delegated_type_families: [
        delegated_type_family(
          owner_entity_id: 'entities/entries',
          owner_ruby_constant: 'Entry',
          association_name: 'entryable',
          foreign_key_columns: ['entryable_id'],
          foreign_type: 'entryable_type',
          targets: [
            delegated_type_target(ruby_constant: 'Post', entity_id: 'entities/posts', status: :selected),
            delegated_type_target(ruby_constant: 'Image', entity_id: 'entities/images', status: :selected),
            delegated_type_target(ruby_constant: 'MissingEntryable', status: :unresolved,
                                  diagnostic_code: 'ASSOCIATION_TARGET_UNRESOLVED')
          ]
        )
      ]
    )

    result = build(
      domain,
      'Entry' => owner_model(belongs_to('entryable', polymorphic: true, dependent: :destroy, touch: true)),
      'Post' => owner_model,
      'Image' => owner_model(image_inverse),
      'Video' => owner_model(undeclared_inverse)
    )

    polymorphic_relationships = result.domains.first.relationships.select do |relationship|
      relationship.relationship_kind == :polymorphic
    end
    relationships = polymorphic_relationships.to_h { |relationship| [relationship.target_entity_id, relationship] }

    expect(relationships.keys).to eq(%w[entities/images entities/posts])
    expect(relationships.fetch('entities/posts')).to have_attributes(
      relationship_id: 'relationships/entries/polymorphic/entryable/entryable_id/entryable_type/posts',
      owner_cardinality: '0..many',
      target_cardinality: '0..1',
      metadata: {
        behavior: {
          from_owner: [
            {
              association_name: 'entryable', association_macro: 'belongs_to',
              dependent: { action: 'destroy', target: 'associated_records' }, touch: { attribute: nil }
            }
          ]
        }
      }
    )
    expect(relationships.fetch('entities/images')).to have_attributes(
      relationship_id: 'relationships/entries/polymorphic/entryable/entryable_id/entryable_type/images',
      owner_cardinality: '0..many',
      target_cardinality: '0..1',
      metadata: {
        scoped: true,
        behavior: {
          from_owner: [
            {
              association_name: 'entryable', association_macro: 'belongs_to',
              dependent: { action: 'destroy', target: 'associated_records' }, touch: { attribute: nil }
            }
          ],
          from_target: [
            {
              association_name: 'entry', association_macro: 'has_one',
              dependent: { action: 'nullify', target: 'associated_records' }
            }
          ]
        }
      }
    )
    expect(result.diagnostics.map { |diagnostic| diagnostic.fetch('code') }).to eq(
      %w[ASSOCIATION_TARGET_UNRESOLVED ASSOCIATION_POLYMORPHIC_OMITTED]
    )
  end

  it 'keeps declared delegated edges while diagnosing invalid inverses in family order' do
    entry_model = renderable_model('Entry', 'entries')
    wrong_owner = renderable_model('OtherEntry', 'other_entries')
    wrong_inverse = association(
      'entries', :has_many, klass: wrong_owner, as: :entryable,
                            foreign_key: 'entryable_id', type: 'entryable_type'
    )
    unresolved_inverse = association(
      'entries', :has_many, class_name: 'MissingEntry', as: :entryable,
                            foreign_key: 'entryable_id', type: 'entryable_type'
    )
    mismatched_keys_inverse = association(
      'entries', :has_many, klass: entry_model, as: :entryable,
                            foreign_key: 'wrong_id', type: 'entryable_type'
    )
    domain = domain_result(
      'core',
      [entity('Entry', 'entries', columns: [column('id', false), column('entryable_id', false),
                                            column('entryable_type', false)]),
       entity('Image', 'images'), entity('Post', 'posts'), entity('Video', 'videos')],
      delegated_type_families: [
        delegated_type_family(
          owner_entity_id: 'entities/entries', owner_ruby_constant: 'Entry', association_name: 'entryable',
          foreign_key_columns: ['entryable_id'], foreign_type: 'entryable_type',
          targets: [
            delegated_type_target(ruby_constant: 'Image', entity_id: 'entities/images', status: :selected),
            delegated_type_target(ruby_constant: 'Post', entity_id: 'entities/posts', status: :selected),
            delegated_type_target(ruby_constant: 'Video', entity_id: 'entities/videos', status: :selected)
          ]
        )
      ]
    )

    result = build(
      domain,
      'Entry' => owner_model(belongs_to('entryable', polymorphic: true)),
      'Image' => owner_model(wrong_inverse),
      'Post' => owner_model(unresolved_inverse),
      'Video' => owner_model(mismatched_keys_inverse)
    )

    expect(result.domains.first.relationships.map(&:target_entity_id)).to eq(
      %w[entities/images entities/posts entities/videos]
    )
    expect(result.diagnostics.map { |diagnostic| diagnostic.fetch('code') }).to eq(
      %w[ASSOCIATION_POLYMORPHIC_OMITTED ASSOCIATION_TARGET_UNRESOLVED ASSOCIATION_POLYMORPHIC_OMITTED]
    )
    expect(result.diagnostics.map { |diagnostic| diagnostic.fetch('subject_id') }).to eq(
      %w[images.entries posts.entries videos.entries]
    )
  end

  it 'emits only the structural root diagnostic for an ineligible delegated family' do
    domain = domain_result(
      'core',
      [entity('Entry', 'entries', columns: [column('id', false), column('entryable_id', false),
                                            column('entryable_type', false)])],
      delegated_type_families: [
        delegated_type_family(
          owner_entity_id: 'entities/entries', owner_ruby_constant: 'Entry', association_name: 'entryable',
          foreign_key_columns: ['entryable_id'], foreign_type: 'entryable_type',
          root_diagnostic_code: 'ASSOCIATION_NON_PRIMARY_KEY_OMITTED',
          targets: [
            delegated_type_target(
              ruby_constant: 'Missing', status: :unresolved,
              diagnostic_code: 'ASSOCIATION_TARGET_UNRESOLVED'
            )
          ]
        )
      ]
    )

    result = build(domain, 'Entry' => owner_model(belongs_to('entryable', polymorphic: true)))

    expect(result.domains.first.relationships).to eq([])
    expect(result.diagnostics.map { |diagnostic| diagnostic.fetch('code') }).to eq(
      ['ASSOCIATION_NON_PRIMARY_KEY_OMITTED']
    )
  end

  it 'fences delegated-expanded entities out of ordinary owner inventory' do
    entry_model = renderable_model('Entry', 'entries')
    message_inverse = association(
      'entries', :has_many, klass: entry_model, as: :entryable,
                            foreign_key: 'entryable_id', type: 'entryable_type', scope: -> { raise 'scope executed' }
    )
    domain = domain_result(
      'core',
      [entity('Entry', 'entries', columns: [column('id', false), column('entryable_id', false),
                                            column('entryable_type', false)]),
       entity('Message', 'messages', columns: [column('id', false), column('author_id', true)],
                                     selection_origin: :delegated_type_expanded),
       entity('Author', 'authors')],
      delegated_type_families: [
        delegated_type_family(
          owner_entity_id: 'entities/entries',
          owner_ruby_constant: 'Entry',
          association_name: 'entryable',
          foreign_key_columns: ['entryable_id'],
          foreign_type: 'entryable_type',
          targets: [
            delegated_type_target(ruby_constant: 'Message', entity_id: 'entities/messages', status: :expanded)
          ]
        )
      ]
    )

    result = build(
      domain,
      'Entry' => owner_model(belongs_to('entryable', polymorphic: true)),
      'Message' => owner_model(
        belongs_to('author', klass: renderable_model('Author', 'authors')),
        message_inverse
      ),
      'Author' => owner_model
    )

    expect(result.domains.first.relationships.map(&:relationship_id)).to eq(
      ['relationships/entries/polymorphic/entryable/entryable_id/entryable_type/messages']
    )
    expect(result.domains.first.relationships.first.metadata).to eq(scoped: true)
    expect(result.diagnostics).to eq([])
  end

  it 'contains unreadable delegated family and target metadata' do
    root = belongs_to('entryable', polymorphic: true)
    entry = entity(
      'Entry', 'entries',
      columns: [column('id', false), column('entryable_id', false), column('entryable_type', false)]
    )
    unreadable_domain = domain_result('core', [entry])
    unreadable_domain.define_singleton_method(:delegated_type_families) { raise 'families unavailable' }

    unreadable_family = delegated_type_family(
      owner_entity_id: 'entities/entries', owner_ruby_constant: 'Entry', association_name: 'entryable',
      foreign_key_columns: ['entryable_id'], foreign_type: 'entryable_type', targets: []
    )
    unreadable_family.define_singleton_method(:targets) { raise 'targets unavailable' }
    family_domain = domain_result('core', [entry], delegated_type_families: [unreadable_family])

    results = [unreadable_domain, family_domain].map do |domain|
      build(domain, 'Entry' => owner_model(root))
    end

    expect(results.map { |result| result.domains.first.relationships }).to eq([[], []])
    expect(results.map { |result| result.diagnostics.first.fetch('code') }).to eq(
      %w[ASSOCIATION_POLYMORPHIC_TARGETS_UNRESOLVED ASSOCIATION_POLYMORPHIC_TARGETS_UNRESOLVED]
    )
  end

  it 'preserves the generic delegated root warning for domain-only target omissions' do
    domain = domain_result(
      'core',
      [entity('Entry', 'entries', columns: [column('id', false), column('entryable_id', false),
                                            column('entryable_type', false)])],
      delegated_type_families: [
        delegated_type_family(
          owner_entity_id: 'entities/entries',
          owner_ruby_constant: 'Entry',
          association_name: 'entryable',
          foreign_key_columns: ['entryable_id'],
          foreign_type: 'entryable_type',
          targets: [
            delegated_type_target(ruby_constant: 'MissingEntryable', status: :unresolved,
                                  diagnostic_code: 'ASSOCIATION_TARGET_UNRESOLVED'),
            delegated_type_target(ruby_constant: 'ElsewhereEntryable', status: :other_domain,
                                  diagnostic_code: 'DOMAIN_RELATIONSHIP_OMITTED'),
            delegated_type_target(ruby_constant: 'HiddenEntryable', status: :not_renderable,
                                  diagnostic_code: 'ASSOCIATION_TARGET_NOT_RENDERABLE_OMITTED')
          ]
        )
      ]
    )

    result = build(domain, 'Entry' => owner_model(belongs_to('entryable', polymorphic: true)))

    expect(result.domains.first.relationships).to eq([])
    expect(result.diagnostics.map { |diagnostic| diagnostic.fetch('code') }).to eq(
      %w[
        ASSOCIATION_TARGET_UNRESOLVED
        DOMAIN_RELATIONSHIP_OMITTED
        ASSOCIATION_TARGET_NOT_RENDERABLE_OMITTED
        ASSOCIATION_POLYMORPHIC_TARGETS_UNRESOLVED
      ]
    )
    expect(result.diagnostics.map { |diagnostic| diagnostic.dig('metadata', 'target_constant') }).to eq(
      ['MissingEntryable', 'ElsewhereEntryable', 'HiddenEntryable', nil]
    )
  end

  it 'stops delegated connection-boundary targets before inverse and key readers' do
    root = belongs_to('entryable', polymorphic: true)
    root.define_singleton_method(:association_primary_key) { raise 'cross-context key reader must not run' }
    inverse = association(
      'entries', :has_many, klass: -> { raise 'cross-context inverse reader must not run' }, as: :entryable
    )
    domain = domain_result(
      'core',
      [entity('Entry', 'entries', columns: [column('id', false), column('entryable_id', false),
                                            column('entryable_type', false)])],
      delegated_type_families: [
        delegated_type_family(
          owner_entity_id: 'entities/entries', owner_ruby_constant: 'Entry', association_name: 'entryable',
          foreign_key_columns: ['entryable_id'], foreign_type: 'entryable_type',
          targets: [delegated_type_target(ruby_constant: 'Message', status: :other_connection,
                                          diagnostic_code: 'CONNECTION_RELATIONSHIP_OMITTED')]
        )
      ]
    )

    result = build(domain, 'Entry' => owner_model(root), 'Message' => owner_model(inverse))

    expect(result.domains.first.relationships).to eq([])
    expect(result.diagnostics.map { |diagnostic| diagnostic.fetch('code') }).to eq(
      ['CONNECTION_RELATIONSHIP_OMITTED']
    )
  end

  it 'builds an inferred-source has-many-through semantic edge beside direct physical edges' do
    membership_model = renderable_model('Membership', 'memberships')
    team_model = renderable_model('Team', 'teams')
    memberships = association('memberships', :has_many, klass: membership_model, foreign_key: 'author_id')
    team_source = belongs_to('team', klass: team_model)
    teams = through_association(
      'teams', :has_many, through_reflection: memberships, source_reflection: team_source, klass: team_model,
                          scope: -> { raise 'scope executed' }
    )
    author = owner_model(memberships, teams)
    membership = owner_model(
      belongs_to('author', klass: renderable_model('Author', 'authors')),
      team_source
    )
    domain = domain_result(
      'core',
      [
        entity('Author', 'authors'),
        entity('Membership', 'memberships',
               columns: [column('id', false), column('author_id', false), column('team_id', false)]),
        entity('Team', 'teams')
      ]
    )

    result = build(domain, 'Author' => author, 'Membership' => membership)
    through = result.domains.first.relationships.find { |relationship| relationship.relationship_kind == :through }

    expect(result.diagnostics).to eq([])
    expect(through).to have_attributes(
      relationship_id: 'relationships/authors/through/memberships/team/teams',
      owner_entity_id: 'entities/authors', target_entity_id: 'entities/teams',
      association_name: 'teams', owner_cardinality: '0..many', target_cardinality: '0..many',
      metadata: { scoped: true }
    )
  end

  it 'omits a through declaration at the first cross-context semantic hop' do
    membership_model = renderable_model('Membership', 'memberships')
    team_model = renderable_model('Team', 'teams')
    memberships = association('memberships', :has_many, klass: membership_model, foreign_key: 'author_id')
    team_source = belongs_to('team', klass: team_model)
    teams = through_association(
      'teams', :has_many, through_reflection: memberships, source_reflection: team_source, klass: team_model
    )
    domain = domain_result(
      'core',
      [
        entity('Author', 'authors'),
        entity('Membership', 'memberships',
               columns: [column('id', false), column('author_id', false), column('team_id', false)],
               connection_context_id: '{"name":"archive"}'),
        entity('Team', 'teams', connection_context_id: '{"name":"archive"}')
      ]
    )

    result = build(
      domain,
      'Author' => owner_model(teams),
      'Membership' => owner_model(team_source),
      'Team' => team_model
    )

    expect(result.domains.first.relationships).not_to include(have_attributes(relationship_kind: :through))
    expect(result.diagnostics).to contain_exactly(
      include(
        'code' => 'CONNECTION_RELATIONSHIP_OMITTED',
        'subject_id' => 'authors.teams',
        'metadata' => include('target_constant' => 'Membership')
      )
    )
  end

  it 'atomically omits a through edge when one physical hop has mismatched key tuples' do
    membership_model = renderable_model('Membership', 'memberships')
    team_model = renderable_model('Team', 'teams')
    memberships = association('memberships', :has_many, klass: membership_model, foreign_key: 'author_id')
    invalid_team_source = belongs_to(
      'team', klass: team_model, foreign_key: %w[tenant_id team_id], association_primary_key: 'id'
    )
    teams = through_association(
      'teams', :has_many,
      through_reflection: memberships,
      source_reflection: invalid_team_source,
      klass: team_model
    )
    domain = domain_result(
      'core',
      [
        entity('Author', 'authors'),
        entity(
          'Membership', 'memberships',
          columns: [column('id', false), column('author_id', false), column('tenant_id', false),
                    column('team_id', false)]
        ),
        entity('Team', 'teams')
      ]
    )

    result = build(domain, 'Author' => owner_model(teams))

    expect(result.domains.first.relationships).to eq([])
    expect(result.diagnostics.map { |diagnostic| diagnostic.fetch('code') }).to eq(
      ['ASSOCIATION_COMPOSITE_KEY_OMITTED']
    )
  end

  it 'omits delegated polymorphic targets when delegated target key columns are absent' do
    post_model = renderable_model('Post', 'posts')
    domain = domain_result(
      'core',
      [
        entity('Comment', 'comments', columns: [column('id', false), column('entryable_id', false),
                                                column('entryable_type', false)]),
        entity('Post', 'posts', columns: [column('entryable_id', false), column('entryable_type', false)],
                                primary_key_columns: ['id'])
      ],
      delegated_type_families: [
        delegated_type_family(
          owner_entity_id: 'entities/comments',
          owner_ruby_constant: 'Comment',
          association_name: 'entryable',
          foreign_key_columns: ['entryable_id'],
          foreign_type: 'entryable_type',
          targets: [delegated_type_target(ruby_constant: 'Post', entity_id: 'entities/posts', status: :selected)]
        )
      ]
    )

    result = build(
      domain,
      'Comment' => owner_model(belongs_to('entryable', polymorphic: true)),
      'Post' => post_model
    )

    expect(result.domains.first.relationships).to eq([])
    expect(result.diagnostics.map { |diagnostic| diagnostic.fetch('code') }).to eq(
      %w[ASSOCIATION_KEY_COLUMN_MISSING ASSOCIATION_POLYMORPHIC_TARGETS_UNRESOLVED]
    )
  end

  it 'omits inverse-free delegated targets whose referenced tuple length mismatches the root tuple' do
    post_model = renderable_model('Post', 'posts')
    domain = domain_result(
      'core',
      [
        entity(
          'Entry', 'entries',
          columns: [column('id', false), column('entryable_region_code', false), column('entryable_id', false),
                    column('entryable_type', false)]
        ),
        entity('Post', 'posts')
      ],
      delegated_type_families: [
        delegated_type_family(
          owner_entity_id: 'entities/entries', owner_ruby_constant: 'Entry', association_name: 'entryable',
          foreign_key_columns: %w[entryable_region_code entryable_id], foreign_type: 'entryable_type',
          targets: [delegated_type_target(ruby_constant: 'Post', entity_id: 'entities/posts', status: :selected)]
        )
      ]
    )
    root = belongs_to(
      'entryable', polymorphic: true, foreign_key: %w[entryable_region_code entryable_id],
                   association_primary_key: 'id'
    )

    result = build(domain, 'Entry' => owner_model(root), 'Post' => post_model)

    expect(result.domains.first.relationships).to eq([])
    expect(result.diagnostics.map { |diagnostic| diagnostic.fetch('code') }).to eq(
      %w[ASSOCIATION_COMPOSITE_KEY_OMITTED ASSOCIATION_POLYMORPHIC_TARGETS_UNRESOLVED]
    )
  end

  it 'omits inverse-free delegated targets whose complete tuple references a missing target member' do
    post_model = renderable_model('Post', 'posts')
    domain = domain_result(
      'core',
      [
        entity(
          'Entry', 'entries',
          columns: [column('id', false), column('entryable_region_code', false), column('entryable_id', false),
                    column('entryable_type', false)]
        ),
        entity('Post', 'posts', primary_key_columns: %w[region_code post_code],
                                columns: [column('region_code', false)])
      ],
      delegated_type_families: [
        delegated_type_family(
          owner_entity_id: 'entities/entries', owner_ruby_constant: 'Entry', association_name: 'entryable',
          foreign_key_columns: %w[entryable_region_code entryable_id], foreign_type: 'entryable_type',
          targets: [delegated_type_target(ruby_constant: 'Post', entity_id: 'entities/posts', status: :selected)]
        )
      ]
    )
    root = belongs_to(
      'entryable', polymorphic: true, foreign_key: %w[entryable_region_code entryable_id],
                   association_primary_key: %w[region_code post_code]
    )

    result = build(domain, 'Entry' => owner_model(root), 'Post' => post_model)

    expect(result.domains.first.relationships).to eq([])
    expect(result.diagnostics.map { |diagnostic| diagnostic.fetch('code') }).to eq(
      %w[ASSOCIATION_KEY_COLUMN_MISSING ASSOCIATION_POLYMORPHIC_TARGETS_UNRESOLVED]
    )
  end

  it 'adds a polymorphic candidate omission when candidate keys and root keys are incompatible' do
    comment_model = renderable_model('Comment', 'comments')
    root = belongs_to(
      'commentable', polymorphic: true, foreign_key: %w[tenant_id commentable_id],
                     foreign_type: 'commentable_type'
    )
    inverse = association(
      'comments', :has_many, klass: comment_model, as: :commentable,
                             foreign_key: %w[tenant_id commentable_id], type: 'commentable_type'
    )
    domain = domain_result(
      'core',
      [
        entity(
          'Comment', 'comments',
          columns: [column('id', false), column('tenant_id', false), column('commentable_id', false),
                    column('commentable_type', false)]
        ),
        entity('Post', 'posts',
               columns: [column('id', false), column('tenant_id', false), column('commentable_id', false)])
      ]
    )

    result = build(domain, 'Comment' => owner_model(root), 'Post' => owner_model(inverse))

    expect(result.diagnostics.map { |diagnostic| diagnostic.fetch('code') }).to eq(
      %w[ASSOCIATION_COMPOSITE_KEY_OMITTED ASSOCIATION_POLYMORPHIC_TARGETS_UNRESOLVED]
    )
  end

  it 'adds a polymorphic key-column omission when candidate references missing keys' do
    comment_model = renderable_model('Comment', 'comments')
    root = belongs_to('commentable', polymorphic: true, foreign_key: 'commentable_id')
    inverse = association(
      'comments', :has_many, klass: comment_model, as: :commentable,
                             foreign_key: 'commentable_id', type: 'commentable_type'
    )
    domain = domain_result(
      'core',
      [
        entity(
          'Comment', 'comments',
          columns: [column('id', false), column('commentable_id', false), column('commentable_type', false)]
        ),
        entity('Post', 'posts', columns: [column('commentable_id', false), column('commentable_type', false)],
                                primary_key_columns: ['id'])
      ]
    )

    result = build(domain, 'Comment' => owner_model(root), 'Post' => owner_model(inverse))

    expect(result.diagnostics.map { |diagnostic| diagnostic.fetch('code') }).to eq(
      %w[ASSOCIATION_KEY_COLUMN_MISSING ASSOCIATION_POLYMORPHIC_TARGETS_UNRESOLVED]
    )
  end

  it 'omits delegated polymorphic candidates when root association_primary_key introspection raises' do
    comment_model = renderable_model('Comment', 'comments')
    root = belongs_to('commentable', polymorphic: true)
    root.define_singleton_method(:association_primary_key) { raise 'unreadable association primary key' }
    inverse = association(
      'comments', :has_many, klass: comment_model, as: :commentable,
                             foreign_key: 'commentable_id', type: 'commentable_type'
    )
    domain = domain_result(
      'core',
      [
        entity(
          'Comment', 'comments',
          columns: [column('id', false), column('commentable_id', false), column('commentable_type', false)]
        ),
        entity('Post', 'posts', columns: [column('id', false), column('commentable_id', false)],
                                primary_key_columns: ['id'])
      ]
    )

    result = build(domain, 'Comment' => owner_model(root), 'Post' => owner_model(inverse))

    expect(result.diagnostics.map { |diagnostic| diagnostic.fetch('code') }).to eq(
      %w[ASSOCIATION_COMPOSITE_KEY_OMITTED ASSOCIATION_POLYMORPHIC_TARGETS_UNRESOLVED]
    )
  end

  it 'publishes inverse-free delegated targets with custom identifier, type, and referenced keys' do
    post_model = renderable_model('Post', 'posts')
    domain = domain_result(
      'core',
      [
        entity(
          'Entry', 'entries',
          columns: [column('id', false), column('entryable_code', false), column('entryable_kind', false)]
        ),
        entity('Post', 'posts', columns: [column('external_code', false)])
      ],
      delegated_type_families: [
        delegated_type_family(
          owner_entity_id: 'entities/entries', owner_ruby_constant: 'Entry', association_name: 'entryable',
          foreign_key_columns: ['entryable_code'], foreign_type: 'entryable_kind',
          targets: [delegated_type_target(ruby_constant: 'Post', entity_id: 'entities/posts', status: :selected)]
        )
      ]
    )
    root = belongs_to(
      'entryable', polymorphic: true, foreign_key: 'entryable_code', foreign_type: 'entryable_kind',
                   association_primary_key: 'external_code', primary_key: 'external_code'
    )

    result = build(domain, 'Entry' => owner_model(root), 'Post' => post_model)

    expect(result.diagnostics).to eq([])
    expect(result.domains.first.relationships).to contain_exactly(
      have_attributes(
        relationship_id: 'relationships/entries/polymorphic/entryable/entryable_code/entryable_kind/posts',
        foreign_key_columns: ['entryable_code'],
        foreign_type_column: 'entryable_kind',
        referenced_key_columns: ['external_code'],
        owner_cardinality: '0..many',
        target_cardinality: '0..1'
      )
    )
  end

  it 'omits belongs_to edges when reflection key extraction raises while normalizing' do
    account_model = renderable_model('Account', 'accounts')
    order = owner_model(belongs_to('account', klass: account_model, foreign_key: lambda {
      raise StandardError, 'invalid key'
    }))
    domain = domain_result(
      'core',
      [entity('Order', 'orders', columns: [column('id', false)]),
       entity('Account', 'accounts', columns: [column('id', false)])]
    )

    result = build(domain, 'Order' => order, 'Account' => account_model)

    expect(result.diagnostics.map { |diagnostic| diagnostic.fetch('code') }).to eq(
      ['ASSOCIATION_COMPOSITE_KEY_OMITTED']
    )
  end

  it 'uses non-belongs_to omission logic for direct through hops' do
    target = entity('Membership', 'memberships', columns: [column('tenant_id', false), column('author_id', false)])
    owner = entity('Author', 'authors', primary_key_columns: ['id'], columns: [column('id', false)])
    reflection = association('memberships', :has_many, foreign_key: %w[tenant_id author_id])

    code = described_class.new(model_resolver: ->(_name) {}).send(
      :direct_hop_key_omission_code,
      owner,
      target,
      renderable_model('Membership', 'memberships'),
      reflection
    )

    expect(code).to eq('ASSOCIATION_COMPOSITE_KEY_OMITTED')
  end

  it 'accepts a complete composite belongs_to through hop' do
    owner = entity(
      'Order', 'orders',
      columns: [column('id', false), column('account_tenant_id', false), column('account_id', false)]
    )
    target = entity(
      'Account', 'accounts', primary_key_columns: %w[tenant_id id],
                             columns: [column('tenant_id', false), column('id', false)]
    )
    reflection = belongs_to(
      'account', foreign_key: %w[account_tenant_id account_id], association_primary_key: %w[tenant_id id]
    )

    code = described_class.new(model_resolver: ->(_name) {}).send(
      :direct_hop_key_omission_code, owner, target, renderable_model('Account', 'accounts'), reflection
    )

    expect(code).to be_nil
  end

  it 'accepts an explicit composite primary key on a belongs_to through hop' do
    owner = entity(
      'Order', 'orders',
      columns: [column('id', false), column('account_tenant_id', false), column('account_id', false)]
    )
    target = entity(
      'Account', 'accounts', primary_key_columns: %w[tenant_id id],
                             columns: [column('tenant_id', false), column('id', false)]
    )
    reflection = belongs_to(
      'account', foreign_key: %w[account_tenant_id account_id], association_primary_key: %w[tenant_id id],
                 primary_key: %w[tenant_id id]
    )

    code = described_class.new(model_resolver: ->(_name) {}).send(
      :direct_hop_key_omission_code, owner, target, renderable_model('Account', 'accounts'), reflection
    )

    expect(code).to be_nil
  end

  it 'accepts an explicit scalar primary key on a belongs_to through hop' do
    owner = entity('Order', 'orders', columns: [column('id', false), column('account_uuid', false)])
    target = entity('Account', 'accounts', columns: [column('id', false), column('uuid', false)])
    reflection = belongs_to(
      'account', foreign_key: 'account_uuid', association_primary_key: 'uuid', primary_key: 'uuid'
    )

    code = described_class.new(model_resolver: ->(_name) {}).send(
      :direct_hop_key_omission_code, owner, target, renderable_model('Account', 'accounts'), reflection
    )

    expect(code).to be_nil
  end

  it 'accepts an explicit composite primary key on a has_many through hop' do
    owner = entity(
      'Account', 'accounts', primary_key_columns: %w[tenant_id id],
                             columns: [column('tenant_id', false), column('id', false)]
    )
    target = entity(
      'Order', 'orders',
      columns: [column('id', false), column('account_tenant_id', false), column('account_id', false)]
    )
    reflection = association(
      'orders', :has_many, foreign_key: %w[account_tenant_id account_id],
                           active_record_primary_key: %w[tenant_id id], primary_key: %w[tenant_id id]
    )

    code = described_class.new(model_resolver: ->(_name) {}).send(
      :direct_hop_key_omission_code, owner, target, renderable_model('Order', 'orders'), reflection
    )

    expect(code).to be_nil
  end

  it 'omits a composite has_many through hop with a missing physical key member' do
    owner = entity(
      'Account', 'accounts', primary_key_columns: %w[tenant_id id],
                             columns: [column('tenant_id', false), column('id', false)]
    )
    target = entity('Order', 'orders', columns: [column('id', false), column('account_id', false)])
    reflection = association(
      'orders', :has_many, foreign_key: %w[account_tenant_id account_id],
                           active_record_primary_key: %w[tenant_id id]
    )

    code = described_class.new(model_resolver: ->(_name) {}).send(
      :direct_hop_key_omission_code, owner, target, renderable_model('Order', 'orders'), reflection
    )

    expect(code).to eq('ASSOCIATION_KEY_COLUMN_MISSING')
  end

  it 'omits a scalar has_many through hop with a missing physical key column' do
    owner = entity('Account', 'accounts')
    target = entity('Order', 'orders')
    reflection = association('orders', :has_many, foreign_key: 'account_id', active_record_primary_key: 'id')

    code = described_class.new(model_resolver: ->(_name) {}).send(
      :direct_hop_key_omission_code, owner, target, renderable_model('Order', 'orders'), reflection
    )

    expect(code).to eq('ASSOCIATION_KEY_COLUMN_MISSING')
  end

  it 'publishes a through edge when its scalar belongs_to source has an explicit primary key' do
    membership_model = renderable_model('Membership', 'memberships')
    account_model = renderable_model('Account', 'accounts')
    memberships = association('memberships', :has_many, klass: membership_model, foreign_key: 'author_id')
    account_source = belongs_to(
      'account', klass: account_model, foreign_key: 'account_uuid', association_primary_key: 'uuid',
                 primary_key: 'uuid'
    )
    accounts = through_association(
      'accounts', :has_many, through_reflection: memberships, source_reflection: account_source,
                             klass: account_model
    )
    domain = domain_result(
      'core',
      [entity('Author', 'authors'),
       entity('Membership', 'memberships',
              columns: [column('id', false), column('author_id', false), column('account_uuid', false)]),
       entity('Account', 'accounts', columns: [column('id', false), column('uuid', false)])]
    )

    result = build(domain, 'Author' => owner_model(accounts))

    expect(result.domains.first.relationships).to contain_exactly(
      have_attributes(
        relationship_id: 'relationships/authors/through/memberships/account/accounts',
        association_name: 'accounts', relationship_kind: :through,
        owner_entity_id: 'entities/authors', target_entity_id: 'entities/accounts'
      )
    )
    expect(result.diagnostics).to eq([])
  end

  it 'omits a public through edge when a scalar physical hop column is missing' do
    membership_model = renderable_model('Membership', 'memberships')
    team_model = renderable_model('Team', 'teams')
    memberships = association('memberships', :has_many, klass: membership_model, foreign_key: 'author_id')
    teams = through_association(
      'teams', :has_many, through_reflection: memberships,
                          source_reflection: belongs_to('team', klass: team_model), klass: team_model
    )
    domain = domain_result(
      'core',
      [entity('Author', 'authors'),
       entity('Membership', 'memberships', columns: [column('id', false), column('team_id', false)]),
       entity('Team', 'teams')]
    )

    result = build(domain, 'Author' => owner_model(teams))

    expect(result.domains.first.relationships).to eq([])
    expect(result.diagnostics.map { |diagnostic| diagnostic.fetch('code') }).to eq(
      ['ASSOCIATION_KEY_COLUMN_MISSING']
    )
  end

  it 'does not relabel unrelated through physical analysis failures as composite omissions' do
    memberships = association('memberships', :has_many, klass: renderable_model('Membership', 'memberships'))
    teams = through_association(
      'teams', :has_many, through_reflection: memberships,
                          source_reflection: belongs_to('team', klass: renderable_model('Team', 'teams')),
                          klass: renderable_model('Team', 'teams')
    )
    owner = entity('Author', 'authors')
    unstable_context = Object.new
    unstable_context.define_singleton_method(:selected_endpoint) { |*| raise 'unreadable domain cache' }
    expect do
      described_class.new(model_resolver: ->(_name) {}).send(
        :through_physical_key_omission_code,
        unstable_context,
        owner,
        teams
      )
    end.to raise_error(RuntimeError, 'unreadable domain cache')
  end

  it 'checks a normalized physical through hop before reading its key binding' do
    team_model = renderable_model('Team', 'teams')
    physical_reflection = belongs_to('team', klass: team_model, foreign_key: -> { raise 'must not bind' })
    hop = described_class::ThroughPhysicalHop.new(
      reflection: physical_reflection, target_model: team_model, target_constant: 'Team'
    )
    builder = described_class.new(model_resolver: ->(_name) { team_model })
    allow(builder).to receive(:through_physical_hops).and_return([[hop], nil, nil])
    domain = domain_result(
      'core', [entity('Author', 'authors'), entity('Team', 'teams', connection_context_id: '{"name":"archive"}')]
    )
    context = described_class::DomainContext.new(domain)

    expect(builder.send(:through_physical_key_omission_code, context, domain.entities.first, Object.new)).to eq(
      %w[CONNECTION_RELATIONSHIP_OMITTED Team]
    )
  end

  it 'retains scope presence from a resolved through source without executing it' do
    membership_model = renderable_model('Membership', 'memberships')
    team_model = renderable_model('Team', 'teams')
    memberships = association('memberships', :has_many, klass: membership_model, foreign_key: 'author_id')
    team_source = belongs_to('team', klass: team_model, scope: -> { raise 'scope executed' })
    teams = through_association(
      'teams', :has_many, through_reflection: memberships, source_reflection: team_source, klass: team_model
    )
    domain = domain_result(
      'core',
      [
        entity('Author', 'authors'),
        entity('Membership', 'memberships',
               columns: [column('id', false), column('author_id', false), column('team_id', false)]),
        entity('Team', 'teams')
      ]
    )

    result = build(domain, 'Author' => owner_model(memberships, teams))
    through = result.domains.first.relationships.find { |relationship| relationship.relationship_kind == :through }

    expect(result.diagnostics).to eq([])
    expect(through).to have_attributes(metadata: { scoped: true })
  end

  it 'publishes only effective outer through behavior from the canonical owner' do
    membership_model = renderable_model('Membership', 'memberships')
    team_model = renderable_model('Team', 'teams')
    memberships = association('memberships', :has_many, klass: membership_model, foreign_key: 'author_id')
    team_source = belongs_to('team', klass: team_model)
    teams = through_association(
      'teams', :has_many, through_reflection: memberships, source_reflection: team_source,
                          klass: team_model, dependent: :delete_all
    )
    domain = domain_result(
      'core',
      [
        entity('Author', 'authors'),
        entity(
          'Membership', 'memberships',
          columns: [column('id', false), column('author_id', false), column('team_id', false)]
        ),
        entity('Team', 'teams')
      ]
    )

    relationship = build(domain, 'Author' => owner_model(memberships, teams))
                   .domains.first.relationships.find { |item| item.relationship_kind == :through }

    expect(relationship.metadata).to eq(
      behavior: {
        from_owner: [
          {
            association_name: 'teams', association_macro: 'has_many',
            dependent: { action: 'delete_all', target: 'through_records' }
          }
        ]
      }
    )
  end

  it 'ignores has-one-through dependent while retaining its touch behavior' do
    membership_model = renderable_model('Membership', 'memberships')
    profile_model = renderable_model('Profile', 'profiles')
    membership = association('membership', :has_one, klass: membership_model, foreign_key: 'author_id')
    profile_source = belongs_to('profile', klass: profile_model)
    profile = through_association(
      'profile', :has_one, through_reflection: membership, source_reflection: profile_source,
                           klass: profile_model, dependent: :destroy, touch: true
    )
    domain = domain_result(
      'core',
      [
        entity('Author', 'authors'),
        entity(
          'Membership', 'memberships',
          columns: [column('id', false), column('author_id', false), column('profile_id', false)]
        ),
        entity('Profile', 'profiles')
      ]
    )

    relationship = build(domain, 'Author' => owner_model(membership, profile))
                   .domains.first.relationships.find { |item| item.relationship_kind == :through }

    expect(relationship.metadata).to eq(
      behavior: {
        from_owner: [
          {
            association_name: 'profile', association_macro: 'has_one', touch: { attribute: nil }
          }
        ]
      }
    )
  end

  it 'uses singular target cardinality for an inferred-source has-one-through edge' do
    account_model = renderable_model('Account', 'accounts')
    account_membership = association(
      'account_membership', :has_one,
      klass: renderable_model('AccountMembership', 'account_memberships'), foreign_key: 'author_id',
      scope: -> { raise 'scope executed' }
    )
    account = through_association(
      'account', :has_one, through_reflection: account_membership,
                           source_reflection: belongs_to('account', klass: account_model), klass: account_model
    )
    domain = domain_result(
      'core',
      [
        entity('Author', 'authors'),
        entity(
          'AccountMembership', 'account_memberships',
          columns: [column('id', false), column('author_id', false), column('account_id', false)]
        ),
        entity('Account', 'accounts')
      ]
    )

    relationship = build(domain, 'Author' => owner_model(account_membership, account))
                   .domains.first.relationships.find { |candidate| candidate.relationship_kind == :through }

    expect(relationship).to have_attributes(
      relationship_id: 'relationships/authors/through/account_membership/account/accounts',
      owner_cardinality: '0..many', target_cardinality: '0..1', metadata: { scoped: true }
    )
  end

  it 'uses the full owner-forward path for nested inferred-source through associations' do
    post_model = renderable_model('Post', 'posts')
    tagging_model = renderable_model('Tagging', 'taggings')
    tag_model = renderable_model('Tag', 'tags')
    posts = association('posts', :has_many, klass: post_model, foreign_key: 'author_id')
    taggings = association('taggings', :has_many, klass: tagging_model, foreign_key: 'post_id')
    inner_tags = through_association(
      'tags', :has_many, through_reflection: taggings,
                         source_reflection: belongs_to('tag', klass: tag_model), klass: tag_model
    )
    tags = through_association(
      'tags', :has_many, through_reflection: posts,
                         source_reflection: inner_tags, klass: tag_model,
                         chain: [association('tags', :has_many, klass: tag_model), taggings, posts]
    )
    domain = domain_result(
      'core',
      [
        entity('Author', 'authors'),
        entity('Post', 'posts', columns: [column('id', false), column('author_id', false)]),
        entity(
          'Tagging', 'taggings',
          columns: [column('id', false), column('post_id', false), column('tag_id', false)]
        ),
        entity('Tag', 'tags')
      ]
    )

    relationship = build(domain, 'Author' => owner_model(posts, tags))
                   .domains.first.relationships.find { |candidate| candidate.relationship_kind == :through }

    expect(relationship).to have_attributes(
      relationship_id: 'relationships/authors/through/posts/taggings/tag/tags',
      through_path: %w[posts taggings tag], target_entity_id: 'entities/tags'
    )
  end

  it 'flattens a nested through reflection on the physical through side' do
    post_model = renderable_model('Post', 'posts')
    tagging_model = renderable_model('Tagging', 'taggings')
    tag_model = renderable_model('Tag', 'tags')
    posts = association('posts', :has_many, klass: post_model, foreign_key: 'author_id')
    taggings = association('taggings', :has_many, klass: tagging_model, foreign_key: 'post_id')
    inner = through_association(
      'taggings', :has_many, through_reflection: posts,
                             source_reflection: taggings, klass: tagging_model
    )
    outer = through_association(
      'tags', :has_many, through_reflection: inner,
                         source_reflection: belongs_to('tag', klass: tag_model), klass: tag_model
    )

    hops, diagnostic_code, = described_class.new(model_resolver: ->(_name) {}).send(
      :through_physical_hops, outer
    )

    expect(hops.map { |hop| hop.reflection.name }).to eq(%w[posts taggings tag])
    expect(diagnostic_code).to be_nil
  end

  it 'deduplicates an identical through path with has-one label priority' do
    membership_model = renderable_model('Membership', 'memberships')
    team_model = renderable_model('Team', 'teams')
    memberships = association('memberships', :has_many, klass: membership_model, foreign_key: 'author_id')
    team_source = belongs_to('team', klass: team_model)
    has_many_teams = through_association(
      'teams', :has_many, through_reflection: memberships, source_reflection: team_source, klass: team_model,
                          scope: -> { raise 'scope executed' }
    )
    has_one_team = through_association(
      'teams', :has_one, through_reflection: memberships, source_reflection: team_source, klass: team_model
    )
    domain = domain_result(
      'core',
      [entity('Author', 'authors'),
       entity('Membership', 'memberships',
              columns: [column('id', false), column('author_id', false), column('team_id', false)]),
       entity('Team', 'teams')]
    )

    through = [owner_model(has_many_teams, has_one_team), owner_model(has_one_team, has_many_teams)].map do |owner|
      build(domain, 'Author' => owner).domains.first.relationships.find do |candidate|
        candidate.relationship_kind == :through
      end
    end

    expect(through).to all(have_attributes(
                             association_macro: :has_one,
                             target_cardinality: '0..1', metadata: { scoped: true }
                           ))
  end

  it 'uses lexical association name for same-macro through path ties' do
    membership_model = renderable_model('Membership', 'memberships')
    team_model = renderable_model('Team', 'teams')
    memberships = association('memberships', :has_many, klass: membership_model, foreign_key: 'author_id')
    team_source = belongs_to('team', klass: team_model)
    teams = through_association(
      'teams', :has_many, through_reflection: memberships, source_reflection: team_source, klass: team_model
    )
    squads = through_association(
      'squads', :has_many, through_reflection: memberships, source_reflection: team_source, klass: team_model
    )
    domain = domain_result(
      'core',
      [entity('Author', 'authors'),
       entity('Membership', 'memberships',
              columns: [column('id', false), column('author_id', false), column('team_id', false)]),
       entity('Team', 'teams')]
    )

    relationship = build(domain, 'Author' => owner_model(teams, squads))
                   .domains.first.relationships.find { |candidate| candidate.relationship_kind == :through }

    expect(relationship.association_name).to eq('squads')
  end

  it 'publishes scoped through edges with explicit source aliases' do
    membership_model = renderable_model('Membership', 'memberships')
    team_model = renderable_model('Team', 'teams')
    memberships = association('memberships', :has_many, klass: membership_model, foreign_key: 'author_id')
    team_source = belongs_to('team', klass: team_model)
    explicit = through_association(
      'teams', :has_many, through_reflection: memberships, source_reflection: team_source, klass: team_model,
                          source: :team, scope: -> { raise 'scope executed' }
    )
    domain = domain_result(
      'core',
      [entity('Author', 'authors'),
       entity('Membership', 'memberships',
              columns: [column('id', false), column('author_id', false), column('team_id', false)]),
       entity('Team', 'teams')]
    )

    result = build(domain, 'Author' => owner_model(explicit))

    expect(result.diagnostics).to eq([])
    expect(result.domains.first.relationships).to contain_exactly(
      have_attributes(
        relationship_id: 'relationships/authors/through/memberships/team/teams',
        through_path: %w[memberships team],
        association_name: 'teams',
        metadata: { scoped: true }
      )
    )
  end

  it 'routes unsupported through variants and ignores aggregate scope indicators' do
    membership_model = renderable_model('Membership', 'memberships')
    team_model = renderable_model('Team', 'teams')
    memberships = association('memberships', :has_many, klass: membership_model, foreign_key: 'author_id')
    team_source = belongs_to('team', klass: team_model)
    owner = owner_model(
      through_association('explicit_teams', :has_many, through_reflection: memberships,
                                                       source_reflection: team_source, klass: team_model,
                                                       source: :team),
      through_association('typed_teams', :has_many, through_reflection: memberships,
                                                    source_reflection: team_source, klass: team_model,
                                                    source_type: 'ManagedTeam'),
      through_association('scoped_teams', :has_many, through_reflection: memberships,
                                                     source_reflection: team_source, klass: team_model,
                                                     has_scope: true),
      association('missing_through', :has_many, through: true),
      association('missing_source', :has_many, through: true, through_reflection: memberships)
    )
    domain = domain_result(
      'core',
      [entity('Author', 'authors'),
       entity('Membership', 'memberships',
              columns: [column('id', false), column('author_id', false), column('team_id', false)]),
       entity('Team', 'teams')]
    )

    result = build(domain, 'Author' => owner)

    expect(result.domains.first.relationships).to contain_exactly(
      have_attributes(association_name: 'explicit_teams', through_path: %w[memberships team], metadata: nil)
    )
    expect(result.diagnostics.map { |diagnostic| diagnostic.fetch('code') }).to eq(
      %w[
        ASSOCIATION_POLYMORPHIC_OMITTED
        ASSOCIATION_THROUGH_UNRESOLVED
        ASSOCIATION_SOURCE_UNRESOLVED
      ]
    )
    expect(result.diagnostics).to all(satisfy { |diagnostic| schema_valid_diagnostic?(diagnostic) })
  end

  it 'applies through physical eligibility checks across nested path hops' do
    post_model = renderable_model('Post', 'posts')
    tagging_model = renderable_model('Tagging', 'taggings')
    tag_model = renderable_model('Tag', 'tags')
    posts = association('posts', :has_many, klass: post_model, foreign_key: 'author_id')
    explicit_taggings = association(
      'taggings', :has_many, klass: tagging_model, foreign_key: 'post_id', source: :tag
    )
    typed_taggings = association(
      'taggings', :has_many, klass: tagging_model, foreign_key: 'post_id', source_type: 'Tag'
    )
    scoped_taggings = association(
      'taggings', :has_many, klass: tagging_model, foreign_key: 'post_id', scope: -> { raise 'scope executed' }
    )
    polymorphic_taggings = association(
      'taggings', :has_many, klass: tagging_model, foreign_key: 'post_id', polymorphic: true
    )
    owner = owner_model(
      nested_through('explicit_tags', posts, explicit_taggings, tag_model),
      nested_through('typed_tags', posts, typed_taggings, tag_model),
      nested_through('scoped_tags', posts, scoped_taggings, tag_model),
      nested_through('polymorphic_tags', posts, polymorphic_taggings, tag_model)
    )
    domain = domain_result(
      'core',
      [entity('Author', 'authors'),
       entity('Post', 'posts',
              columns: [column('id', false), column('author_id', false), column('tag_id', false)]),
       entity('Tagging', 'taggings',
              columns: [column('id', false), column('post_id', false), column('tag_id', false)]),
       entity('Tag', 'tags')]
    )

    result = build(domain, 'Author' => owner)

    expect(result.domains.first.relationships).to contain_exactly(
      have_attributes(
        association_name: 'explicit_tags',
        through_path: %w[posts taggings tag],
        metadata: { scoped: true }
      )
    )
    expect(result.diagnostics).to eq([])
  end

  it 'finds nested explicit sources through source-reflection lineage and rejects invalid typed ones' do
    post_model = renderable_model('Post', 'posts')
    labeling_model = renderable_model('Labeling', 'labelings')
    label_model = renderable_model('Label', 'labels')
    posts = association('posts', :has_many, klass: post_model, foreign_key: 'author_id')
    labelings = association('labelings', :has_many, klass: labeling_model, foreign_key: 'post_id')
    label_source = belongs_to('label', klass: label_model)
    explicit_inner = through_association(
      'labels', :has_many, through_reflection: labelings,
                           source_reflection: label_source, klass: label_model, source: :label
    )
    typed_inner = through_association(
      'labels', :has_many, through_reflection: labelings,
                           source_reflection: label_source, klass: label_model, source_type: 'ManagedLabel'
    )
    outer = lambda do |inner|
      through_association(
        'labels', :has_many, through_reflection: posts, source_reflection: inner, klass: label_model,
                             chain: [association('labels', :has_many, klass: label_model), labelings, posts]
      )
    end
    domain = domain_result(
      'core',
      [
        entity('Author', 'authors'),
        entity('Post', 'posts', columns: [column('id', false), column('author_id', false)]),
        entity('Labeling', 'labelings',
               columns: [column('id', false), column('post_id', false), column('label_id', false)]),
        entity('Label', 'labels')
      ]
    )

    explicit_result = build(domain, 'Author' => owner_model(outer.call(explicit_inner)))
    typed_result = build(domain, 'Author' => owner_model(outer.call(typed_inner)))

    expect(explicit_result.diagnostics).to eq([])
    expect(explicit_result.domains.first.relationships).to contain_exactly(
      have_attributes(
        relationship_id: 'relationships/authors/through/posts/labelings/label/labels',
        through_path: %w[posts labelings label]
      )
    )
    expect(typed_result.diagnostics.map { |diagnostic| diagnostic.fetch('code') }).to eq(
      ['ASSOCIATION_POLYMORPHIC_OMITTED']
    )
  end

  it 'publishes typed polymorphic through edges with custom identifier, type, and referenced keys' do
    tagging_model = renderable_model('Tagging', 'taggings')
    article_model = renderable_model('Article', 'articles')
    taggings = association('taggings', :has_many, klass: tagging_model, foreign_key: 'author_id')
    article_source = belongs_to(
      'taggable', polymorphic: true, foreign_key: 'taggable_ref',
                  foreign_type: 'taggable_kind', association_primary_key: 'slug', primary_key: 'slug'
    )
    articles = through_association(
      'articles', :has_many,
      through_reflection: taggings,
      source_reflection: article_source,
      klass: article_model,
      source_type: 'Article',
      chain: [article_source, taggings]
    )
    author = owner_model(taggings, articles)
    domain = domain_result(
      'core',
      [
        entity('Author', 'authors'),
        entity(
          'Tagging', 'taggings',
          columns: [column('id', false), column('author_id', false), column('taggable_ref', false),
                    column('taggable_kind', false)]
        ),
        entity('Article', 'articles', columns: [column('slug', false)])
      ]
    )

    result = build(domain, 'Author' => author, 'Tagging' => tagging_model)
    through = result.domains.first.relationships.find { |relationship| relationship.relationship_kind == :through }

    expect(result.diagnostics).to eq([])
    expect(through).to have_attributes(
      relationship_id: 'relationships/authors/through/taggings/taggable/articles',
      through_path: %w[taggings taggable],
      target_entity_id: 'entities/articles',
      metadata: nil
    )
  end

  it 'reuses renderability and domain diagnostics after through models resolve' do
    team_model = renderable_model('Team', 'teams')
    hidden_memberships = association(
      'hidden_memberships', :has_many,
      klass: renderable_model('HiddenMembership', 'hidden_memberships', renderable: false)
    )
    memberships = association(
      'memberships', :has_many, klass: renderable_model('Membership', 'memberships')
    )
    owner = owner_model(
      through_association('hidden_teams', :has_many, through_reflection: hidden_memberships,
                                                     source_reflection: belongs_to('team', klass: team_model),
                                                     klass: team_model),
      through_association('external_teams', :has_many, through_reflection: memberships,
                                                       source_reflection: belongs_to('team', klass: team_model),
                                                       klass: team_model)
    )
    domain = domain_result(
      'core', [entity('Author', 'authors'), entity('HiddenMembership', 'hidden_memberships'),
               entity('Membership', 'memberships')]
    )

    result = build(domain, 'Author' => owner)

    expect(result.domains.first.relationships).to eq([])
    expect(result.diagnostics.map { |diagnostic| diagnostic.fetch('code') }).to eq(
      %w[ASSOCIATION_TARGET_NOT_RENDERABLE_OMITTED DOMAIN_RELATIONSHIP_OMITTED]
    )
  end

  it 'stabilizes an unreadable nested join chain as source unresolved' do
    membership_model = renderable_model('Membership', 'memberships')
    team_model = renderable_model('Team', 'teams')
    memberships = association('memberships', :has_many, klass: membership_model, foreign_key: 'author_id')
    teams = through_association(
      'teams', :has_many, through_reflection: memberships,
                          source_reflection: belongs_to('team', klass: team_model), klass: team_model,
                          chain: -> { raise ArgumentError, 'invalid nested chain' }
    )
    domain = domain_result(
      'core',
      [entity('Author', 'authors'),
       entity('Membership', 'memberships',
              columns: [column('id', false), column('author_id', false), column('team_id', false)]),
       entity('Team', 'teams')]
    )

    result = build(domain, 'Author' => owner_model(teams))

    expect(result.domains.first.relationships).to eq([])
    expect(result.diagnostics.map { |diagnostic| diagnostic.fetch('code') }).to eq(
      ['ASSOCIATION_SOURCE_UNRESOLVED']
    )
  end

  it 'ignores unreadable aggregate through scope state when no scope proc exists' do
    membership_model = renderable_model('Membership', 'memberships')
    team_model = renderable_model('Team', 'teams')
    memberships = association('memberships', :has_many, klass: membership_model, foreign_key: 'author_id')
    teams = through_association(
      'teams', :has_many, through_reflection: memberships,
                          source_reflection: belongs_to('team', klass: team_model), klass: team_model,
                          has_scope: -> { raise NoMethodError, 'missing source scope state' }
    )
    domain = domain_result(
      'core',
      [entity('Author', 'authors'),
       entity('Membership', 'memberships',
              columns: [column('id', false), column('author_id', false), column('team_id', false)]),
       entity('Team', 'teams')]
    )

    result = build(domain, 'Author' => owner_model(teams))

    expect(result.domains.first.relationships).to contain_exactly(
      have_attributes(association_name: 'teams', metadata: nil)
    )
    expect(result.diagnostics).to eq([])
  end

  it 'stabilizes unreadable nested source lineage as source unresolved' do
    post_model = renderable_model('Post', 'posts')
    label_model = renderable_model('Label', 'labels')
    posts = association('posts', :has_many, klass: post_model, foreign_key: 'author_id')
    missing_inner_source = association(
      'labels', :has_many, through: true,
                           source_reflection: -> { raise ArgumentError, 'invalid inner source' }, klass: label_model
    )
    broken_options_source = through_association(
      'labels', :has_many,
      through_reflection: association('labelings', :has_many, klass: renderable_model('Labeling', 'labelings'),
                                                              foreign_key: 'post_id'),
      source_reflection: belongs_to('label', klass: label_model),
      klass: label_model
    )
    broken_options_source.define_singleton_method(:options) { raise ArgumentError, 'invalid source options' }
    outer = lambda do |source|
      through_association(
        'labels', :has_many, through_reflection: posts, source_reflection: source, klass: label_model
      )
    end
    domain = domain_result(
      'core', [entity('Author', 'authors'), entity('Post', 'posts'), entity('Label', 'labels')]
    )

    codes = [missing_inner_source, broken_options_source].map do |source|
      build(domain, 'Author' => owner_model(outer.call(source))).diagnostics.first.fetch('code')
    end

    expect(codes).to eq(%w[ASSOCIATION_SOURCE_UNRESOLVED ASSOCIATION_SOURCE_UNRESOLVED])
  end

  it 'uses scope fallback and rejects unsafe names on nested join-chain hops' do
    post_model = renderable_model('Post', 'posts')
    labeling_model = renderable_model('Labeling', 'labelings')
    label_model = renderable_model('Label', 'labels')
    posts = association('posts', :has_many, klass: post_model, foreign_key: 'author_id')
    label_source = belongs_to('label', klass: label_model)
    scoped_hop = scope_only_reflection('labelings', labeling_model, foreign_key: 'post_id')
    unsafe_hop = association('BadName', :has_many, klass: labeling_model)
    outer = lambda do |name, hop|
      through_association(
        name, :has_many, through_reflection: posts, source_reflection: label_source, klass: label_model,
                         chain: [association(name, :has_many, klass: label_model), hop, posts]
      )
    end
    owner = owner_model(outer.call('scoped_labels', scoped_hop), outer.call('unsafe_labels', unsafe_hop))
    domain = domain_result(
      'core',
      [entity('Author', 'authors'),
       entity('Post', 'posts',
              columns: [column('id', false), column('author_id', false), column('label_id', false)]),
       entity('Labeling', 'labelings',
              columns: [column('id', false), column('post_id', false), column('label_id', false)]),
       entity('Label', 'labels')]
    )

    result = build(domain, 'Author' => owner)

    expect(result.domains.first.relationships).to contain_exactly(
      have_attributes(association_name: 'scoped_labels', metadata: { scoped: true })
    )
    expect(result.diagnostics.map { |diagnostic| diagnostic.fetch('code') }).to eq(
      %w[ASSOCIATION_NAME_UNSUPPORTED_OMITTED]
    )
  end

  it 'degrades direct-has key reader failures without misreporting target resolution' do
    profile = renderable_model('Profile', 'profiles')
    author = owner_model(
      association('profiles', :has_many, klass: profile, foreign_key: -> { raise ArgumentError, 'invalid inverse' })
    )
    domain = domain_result('core', [entity('Author', 'authors'), entity('Profile', 'profiles')])

    result = build(domain, 'Author' => author)

    expect(result.domains.first.relationships).to eq([])
    expect(result.diagnostics.map { |diagnostic| diagnostic.fetch('code') }).to eq(
      ['ASSOCIATION_COMPOSITE_KEY_OMITTED']
    )
  end

  it 'publishes direct belongs_to, has_many, and has_one bindings with explicit primary keys' do
    account_model = renderable_model('Account', 'accounts')
    order_model = renderable_model('Order', 'orders')
    membership_model = renderable_model('Membership', 'memberships')
    profile_model = renderable_model('Profile', 'profiles')
    order = owner_model(
      belongs_to(
        'account', klass: account_model, foreign_key: 'account_code',
                   association_primary_key: 'external_code', primary_key: 'external_code'
      )
    )
    account = owner_model(
      association(
        'orders', :has_many, klass: order_model, foreign_key: 'account_code',
                             active_record_primary_key: 'external_code', primary_key: 'external_code'
      ),
      association(
        'memberships', :has_many, klass: membership_model, foreign_key: 'account_code',
                                  active_record_primary_key: 'external_code', primary_key: 'external_code',
                                  type: 'ignored_without_as'
      ),
      association(
        'profile', :has_one, klass: profile_model, foreign_key: 'account_code',
                             active_record_primary_key: 'external_code', primary_key: 'external_code'
      )
    )
    domain = domain_result(
      'core',
      [
        entity('Account', 'accounts', columns: [column('id', false), column('external_code', false)]),
        entity('Order', 'orders', columns: [column('id', false), column('account_code', true)]),
        entity('Membership', 'memberships', columns: [column('id', false), column('account_code', true)]),
        entity('Profile', 'profiles', columns: [column('id', false), column('account_code', true)])
      ]
    )

    result = build(
      domain,
      'Account' => account, 'Order' => order,
      'Membership' => membership_model, 'Profile' => profile_model
    )

    expect(result.domains.first.relationships).to contain_exactly(
      have_attributes(
        relationship_id: 'relationships/orders/account_code/accounts/external_code',
        association_name: 'account', association_macro: :belongs_to,
        foreign_key_columns: ['account_code'], referenced_key_columns: ['external_code']
      ),
      have_attributes(
        relationship_id: 'relationships/memberships/account_code/accounts/external_code',
        association_name: 'memberships', association_macro: :has_many,
        foreign_key_columns: ['account_code'], referenced_key_columns: ['external_code']
      ),
      have_attributes(
        relationship_id: 'relationships/profiles/account_code/accounts/external_code',
        association_name: 'profile', association_macro: :has_one,
        foreign_key_columns: ['account_code'], referenced_key_columns: ['external_code']
      )
    )
    expect(result.diagnostics).to eq([])
  end

  it 'reuses target and key omission diagnostics for ineligible direct has associations' do
    profile = renderable_model('Profile', 'profiles')
    author = owner_model(
      association('legacy_profiles', :has_many,
                  klass: renderable_model('LegacyProfile', 'legacy_profiles', renderable: false)),
      association('uuid_profiles', :has_many, klass: profile, foreign_key: 'author_id',
                                              active_record_primary_key: 'uuid', primary_key: 'uuid'),
      association('missing_key_profiles', :has_many, klass: profile, foreign_key: 'missing_author_id')
    )
    domain = domain_result(
      'core',
      [entity('Author', 'authors'),
       entity('Profile', 'profiles', columns: [column('id', false), column('author_id', true)])]
    )

    result = build(domain, 'Author' => author)

    expect(result.domains.first.relationships).to eq([])
    expect(result.diagnostics.map { |diagnostic| diagnostic.fetch('code') }).to eq(
      %w[
        ASSOCIATION_TARGET_NOT_RENDERABLE_OMITTED
        ASSOCIATION_KEY_COLUMN_MISSING
        ASSOCIATION_KEY_COLUMN_MISSING
      ]
    )
  end

  it 'prefers an existing belongs_to over a physical-key-equivalent direct has edge' do
    post = owner_model(belongs_to('author', klass: renderable_model('Author', 'authors')))
    author = owner_model(
      association('posts', :has_many, klass: renderable_model('Post', 'posts'), foreign_key: 'author_id')
    )
    domain = domain_result(
      'core',
      [
        entity('Post', 'posts', columns: [column('id', false), column('author_id', true)]),
        entity('Author', 'authors')
      ]
    )

    result = build(domain, 'Post' => post, 'Author' => author)

    expect(result.diagnostics).to eq([])
    expect(result.domains.first.relationships.map(&:relationship_id)).to eq(
      ['relationships/posts/author_id/authors/id']
    )
  end

  it 'uses macro priority and lexical declaration ID for canonical label ties' do
    author_model = renderable_model('Author', 'authors')
    scoped = belongs_to('writer', klass: author_model, class_name: 'Author', foreign_key: 'author_id',
                                  scope: -> { raise 'scope executed' })
    unscoped = belongs_to('author', klass: author_model, foreign_key: 'author_id')
    domain = domain_result(
      'core',
      [entity('Post', 'posts', columns: [column('id', false), column('author_id', true)]), entity('Author', 'authors')]
    )

    relationships = [owner_model(scoped, unscoped), owner_model(unscoped, scoped)].map do |post|
      build(domain, 'Post' => post).domains.first.relationships.fetch(0)
    end

    expect(relationships).to all(have_attributes(
                                   relationship_id: 'relationships/posts/author_id/authors/id',
                                   association_name: 'author', metadata: { scoped: true }
                                 ))
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
      belongs_to('uuid_account', class_name: 'Account', association_primary_key: 'uuid', primary_key: 'uuid'),
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
        ASSOCIATION_TARGET_UNRESOLVED
        ASSOCIATION_TARGET_UNRESOLVED
        ASSOCIATION_TARGET_NOT_RENDERABLE_OMITTED
        DOMAIN_RELATIONSHIP_OMITTED
        ASSOCIATION_COMPOSITE_KEY_OMITTED
        ASSOCIATION_KEY_COLUMN_MISSING
        ASSOCIATION_KEY_COLUMN_MISSING
        ASSOCIATION_NAME_UNSUPPORTED_OMITTED
        ASSOCIATION_KEY_COLUMN_MISSING
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

  DelegatedTypeFamily = Struct.new(
    :owner_entity_id,
    :owner_ruby_constant,
    :association_name,
    :foreign_key_columns,
    :foreign_type,
    :scoped,
    :root_diagnostic_code,
    :targets,
    keyword_init: true
  )
  DelegatedTypeTarget = Struct.new(
    :ruby_constant,
    :entity_id,
    :status,
    :diagnostic_code,
    keyword_init: true
  )

  def domain_result(domain_id, entities, join_tables: [], delegated_type_families: [])
    RailsMmd::SchemaProbe::DomainResult.new(
      domain_id: domain_id, entities: entities, join_tables: join_tables, diagnostics: []
    ).tap do |result|
      next if delegated_type_families.empty?

      result.define_singleton_method(:delegated_type_families) { delegated_type_families }
    end
  end

  def entity(ruby_constant, table_name, columns: [column('id', false)], primary_key_columns: ['id'], foreign_keys: [],
             indexes: [], selection_origin: nil, connection_context_id: '{"name":"primary"}')
    attributes = entity_attributes(
      ruby_constant:, table_name:, columns:, primary_key_columns:, foreign_keys:, indexes:, connection_context_id:
    )

    decorate_entity_selection_origin(RailsMmd::SchemaProbe::Entity.new(**attributes), selection_origin)
  end

  def entity_attributes(ruby_constant:, table_name:, columns:, primary_key_columns:, foreign_keys:, indexes:,
                        connection_context_id:)
    {
      ruby_constant: ruby_constant,
      table_name: table_name,
      connection_context_id: connection_context_id,
      columns: columns,
      primary_key_columns: primary_key_columns,
      foreign_keys: foreign_keys,
      indexes: indexes
    }
  end

  def decorate_entity_selection_origin(result, selection_origin)
    result.tap do
      next if selection_origin.nil?

      result.define_singleton_method(:selection_origin) { selection_origin }
    end
  end

  def delegated_type_family(**attributes)
    DelegatedTypeFamily.new(**attributes)
  end

  def delegated_type_target(**attributes)
    DelegatedTypeTarget.new(**attributes)
  end

  def column(name, nullable)
    RailsMmd::SchemaProbe::Column.new(name: name, type: :integer, nullable: nullable)
  end

  def foreign_key(from_table, columns, to_table, primary_key_columns)
    RailsMmd::SchemaProbe::ForeignKey.new(
      from_table: from_table,
      columns: Array(columns),
      to_table: to_table,
      primary_key_columns: Array(primary_key_columns)
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

  def join_table(table_name, column_names, primary_key_columns: nil,
                 connection_context_id: '{"name":"primary"}')
    RailsMmd::SchemaProbe::JoinTable.new(
      table_name: table_name,
      connection_context_id: connection_context_id,
      columns: column_names.map do |name|
        RailsMmd::SchemaProbe::Column.new(name: name, type: :integer, nullable: false)
      end,
      primary_key_columns: primary_key_columns
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

  def association(name, macro, options = {})
    Reflection.new(name, macro, options)
  end

  def through_association(name, macro, through_reflection:, source_reflection:, klass:, chain: nil, **options)
    reflection = Reflection.new(
      name, macro,
      options.merge(through: true, through_reflection: through_reflection,
                    source_reflection: source_reflection, klass: klass)
    )
    reflection.options[:collect_join_chain] = chain || [reflection, through_reflection]
    reflection
  end

  def nested_through(name, root, middle, target_model)
    through_association(
      name, :has_many, through_reflection: root,
                       source_reflection: belongs_to('tag', klass: target_model), klass: target_model,
                       chain: [association(name, :has_many, klass: target_model), middle, root]
    )
  end

  def scope_only_reflection(name, model, foreign_key:)
    reflection = Object.new
    reflection.define_singleton_method(:name) { name }
    reflection.define_singleton_method(:macro) { :has_many }
    reflection.define_singleton_method(:scope) { -> {} }
    reflection.define_singleton_method(:polymorphic?) { false }
    reflection.define_singleton_method(:klass) { model }
    reflection.define_singleton_method(:foreign_key) { foreign_key }
    reflection.define_singleton_method(:active_record_primary_key) { 'id' }
    reflection
  end

  def unreadable_polymorphic_inverse(model)
    reflection = association('comments', :has_many, klass: model, type: 'commentable_type')
    reflection.define_singleton_method(:options) { raise 'options unavailable' }
    reflection
  end

  def simple_reflection(name)
    Struct.new(:name, :macro, :foreign_key, :association_primary_key) do
      def polymorphic? = false

      def scope = nil
    end.new(name, :belongs_to, "#{name}_id", 'id')
  end

  class Reflection
    attr_reader :name, :macro, :options

    def initialize(name, macro, options)
      @name = name
      @macro = macro
      @options = options
    end

    def polymorphic? = @options.fetch(:polymorphic, false)

    def scope = @options[:scope]

    def foreign_key
      value = @options.fetch(:foreign_key, "#{name}_id")
      value.respond_to?(:call) ? value.call : value
    end

    def association_primary_key(_target_model = nil) = @options.fetch(:association_primary_key, 'id')

    def foreign_type = @options.fetch(:foreign_type, "#{name}_type")

    def association_foreign_key = @options[:association_foreign_key]

    def join_table = @options[:join_table]

    def active_record_primary_key = @options.fetch(:active_record_primary_key, 'id')

    def through_reflection? = @options.fetch(:through, false)

    def through_reflection = @options[:through_reflection]

    def source_reflection
      value = @options[:source_reflection]
      value.respond_to?(:call) ? value.call : value
    end

    def collect_join_chain
      value = @options.fetch(:collect_join_chain)
      value.respond_to?(:call) ? value.call : value
    end

    def has_scope?
      value = @options.fetch(:has_scope, false)
      value.respond_to?(:call) ? value.call : value
    end

    def type = @options[:type]

    def class_name = @options.fetch(:class_name, name.split('_').map(&:capitalize).join)

    def counter_cache_column = @options[:counter_cache_column]

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
