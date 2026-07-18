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
      ['ASSOCIATION_TARGET_UNRESOLVED']
    )
  end

  it 'resolves supported has macros and leaves other macros generic' do
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
      ['authors.tags', 'ASSOCIATION_MACRO_OMITTED', 'has_and_belongs_to_many']
    )
    expect(result.diagnostics).to all(satisfy { |diagnostic| schema_valid_diagnostic?(diagnostic) })
  end

  it 'builds inverse-free direct has relationships from target-side FK evidence' do
    author = owner_model(
      association('profiles', :has_many, klass: renderable_model('Profile', 'profiles'), foreign_key: 'author_id'),
      association('account', :has_one, klass: renderable_model('Account', 'accounts'), foreign_key: 'author_id')
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
      foreign_key_holder_entity_id: 'entities/profiles', foreign_key_column: 'author_id',
      owner_cardinality: '0..many', target_cardinality: '0..1'
    )
    expect(relationships.fetch('account')).to have_attributes(
      relationship_id: 'relationships/accounts/author_id/authors/id',
      owner_entity_id: 'entities/accounts', target_entity_id: 'entities/authors',
      foreign_key_holder_entity_id: 'entities/accounts', foreign_key_column: 'author_id',
      owner_cardinality: '0..1', target_cardinality: '1..1'
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
      %w[ASSOCIATION_THROUGH_UNRESOLVED ASSOCIATION_SCOPED_OMITTED ASSOCIATION_POLYMORPHIC_OMITTED]
    )
  end

  it 'builds an inferred-source has-many-through semantic edge beside direct physical edges' do
    membership_model = renderable_model('Membership', 'memberships')
    team_model = renderable_model('Team', 'teams')
    memberships = association('memberships', :has_many, klass: membership_model, foreign_key: 'author_id')
    team_source = belongs_to('team', klass: team_model)
    teams = through_association(
      'teams', :has_many, through_reflection: memberships, source_reflection: team_source, klass: team_model
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
      association_name: 'teams', owner_cardinality: '0..many', target_cardinality: '0..many'
    )
  end

  it 'uses singular target cardinality for an inferred-source has-one-through edge' do
    account_model = renderable_model('Account', 'accounts')
    account_membership = association(
      'account_membership', :has_one,
      klass: renderable_model('AccountMembership', 'account_memberships'), foreign_key: 'author_id'
    )
    account = through_association(
      'account', :has_one, through_reflection: account_membership,
                           source_reflection: belongs_to('account', klass: account_model), klass: account_model
    )
    domain = domain_result(
      'core',
      [entity('Author', 'authors'), entity('AccountMembership', 'account_memberships'), entity('Account', 'accounts')]
    )

    relationship = build(domain, 'Author' => owner_model(account_membership, account))
                   .domains.first.relationships.find { |candidate| candidate.relationship_kind == :through }

    expect(relationship).to have_attributes(
      relationship_id: 'relationships/authors/through/account_membership/account/accounts',
      owner_cardinality: '0..many', target_cardinality: '0..1'
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
      [entity('Author', 'authors'), entity('Post', 'posts'), entity('Tagging', 'taggings'), entity('Tag', 'tags')]
    )

    relationship = build(domain, 'Author' => owner_model(posts, tags))
                   .domains.first.relationships.find { |candidate| candidate.relationship_kind == :through }

    expect(relationship).to have_attributes(
      relationship_id: 'relationships/authors/through/posts/taggings/tag/tags',
      through_path: %w[posts taggings tag], target_entity_id: 'entities/tags'
    )
  end

  it 'deduplicates an identical through path with has-one label priority' do
    membership_model = renderable_model('Membership', 'memberships')
    team_model = renderable_model('Team', 'teams')
    memberships = association('memberships', :has_many, klass: membership_model)
    team_source = belongs_to('team', klass: team_model)
    has_many_teams = through_association(
      'teams', :has_many, through_reflection: memberships, source_reflection: team_source, klass: team_model
    )
    has_one_team = through_association(
      'teams', :has_one, through_reflection: memberships, source_reflection: team_source, klass: team_model
    )
    domain = domain_result(
      'core', [entity('Author', 'authors'), entity('Membership', 'memberships'), entity('Team', 'teams')]
    )

    through = build(domain, 'Author' => owner_model(has_many_teams, has_one_team))
              .domains.first.relationships.select { |candidate| candidate.relationship_kind == :through }

    expect(through).to contain_exactly(
      have_attributes(association_macro: :has_one, target_cardinality: '0..1')
    )
  end

  it 'uses lexical association name for same-macro through path ties' do
    membership_model = renderable_model('Membership', 'memberships')
    team_model = renderable_model('Team', 'teams')
    memberships = association('memberships', :has_many, klass: membership_model)
    team_source = belongs_to('team', klass: team_model)
    teams = through_association(
      'teams', :has_many, through_reflection: memberships, source_reflection: team_source, klass: team_model
    )
    squads = through_association(
      'squads', :has_many, through_reflection: memberships, source_reflection: team_source, klass: team_model
    )
    domain = domain_result(
      'core', [entity('Author', 'authors'), entity('Membership', 'memberships'), entity('Team', 'teams')]
    )

    relationship = build(domain, 'Author' => owner_model(teams, squads))
                   .domains.first.relationships.find { |candidate| candidate.relationship_kind == :through }

    expect(relationship.association_name).to eq('squads')
  end

  it 'routes unsupported and unresolved through variants to stable diagnostics' do
    membership_model = renderable_model('Membership', 'memberships')
    team_model = renderable_model('Team', 'teams')
    memberships = association('memberships', :has_many, klass: membership_model)
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
      'core', [entity('Author', 'authors'), entity('Membership', 'memberships'), entity('Team', 'teams')]
    )

    result = build(domain, 'Author' => owner)

    expect(result.domains.first.relationships).to eq([])
    expect(result.diagnostics.map { |diagnostic| diagnostic.fetch('code') }).to eq(
      %w[
        ASSOCIATION_MACRO_OMITTED
        ASSOCIATION_POLYMORPHIC_OMITTED
        ASSOCIATION_SCOPED_OMITTED
        ASSOCIATION_THROUGH_UNRESOLVED
        ASSOCIATION_SOURCE_UNRESOLVED
      ]
    )
    expect(result.diagnostics).to all(satisfy { |diagnostic| schema_valid_diagnostic?(diagnostic) })
  end

  it 'applies through eligibility checks to every nested hop' do
    post_model = renderable_model('Post', 'posts')
    tag_model = renderable_model('Tag', 'tags')
    posts = association('posts', :has_many, klass: post_model)
    owner = owner_model(
      nested_through('explicit_tags', posts, association('taggings', :has_many, source: :tag), tag_model),
      nested_through('typed_tags', posts, association('taggings', :has_many, source_type: 'Tag'), tag_model),
      nested_through('scoped_tags', posts, association('taggings', :has_many, scope: -> {}), tag_model),
      nested_through('polymorphic_tags', posts, association('taggings', :has_many, polymorphic: true), tag_model)
    )
    domain = domain_result(
      'core', [entity('Author', 'authors'), entity('Post', 'posts'), entity('Tagging', 'taggings'),
               entity('Tag', 'tags')]
    )

    result = build(domain, 'Author' => owner)

    expect(result.domains.first.relationships).to eq([])
    expect(result.diagnostics.map { |diagnostic| diagnostic.fetch('code') }).to eq(
      %w[
        ASSOCIATION_MACRO_OMITTED
        ASSOCIATION_POLYMORPHIC_OMITTED
        ASSOCIATION_SCOPED_OMITTED
        ASSOCIATION_POLYMORPHIC_OMITTED
      ]
    )
  end

  it 'finds nested explicit and typed sources through source-reflection lineage' do
    post_model = renderable_model('Post', 'posts')
    labeling_model = renderable_model('Labeling', 'labelings')
    label_model = renderable_model('Label', 'labels')
    posts = association('posts', :has_many, klass: post_model)
    labelings = association('labelings', :has_many, klass: labeling_model)
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
      'core', [entity('Author', 'authors'), entity('Post', 'posts'),
               entity('Labeling', 'labelings'), entity('Label', 'labels')]
    )

    codes = [explicit_inner, typed_inner].map do |inner|
      build(domain, 'Author' => owner_model(outer.call(inner))).diagnostics.first.fetch('code')
    end

    expect(codes).to eq(%w[ASSOCIATION_MACRO_OMITTED ASSOCIATION_POLYMORPHIC_OMITTED])
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
    memberships = association('memberships', :has_many, klass: membership_model)
    teams = through_association(
      'teams', :has_many, through_reflection: memberships,
                          source_reflection: belongs_to('team', klass: team_model), klass: team_model,
                          chain: -> { raise ArgumentError, 'invalid nested chain' }
    )
    domain = domain_result(
      'core', [entity('Author', 'authors'), entity('Membership', 'memberships'), entity('Team', 'teams')]
    )

    result = build(domain, 'Author' => owner_model(teams))

    expect(result.domains.first.relationships).to eq([])
    expect(result.diagnostics.map { |diagnostic| diagnostic.fetch('code') }).to eq(
      ['ASSOCIATION_SOURCE_UNRESOLVED']
    )
  end

  it 'stabilizes an unreadable Rails through scope state as source unresolved' do
    membership_model = renderable_model('Membership', 'memberships')
    team_model = renderable_model('Team', 'teams')
    memberships = association('memberships', :has_many, klass: membership_model)
    teams = through_association(
      'teams', :has_many, through_reflection: memberships,
                          source_reflection: belongs_to('team', klass: team_model), klass: team_model,
                          has_scope: -> { raise NoMethodError, 'missing source scope state' }
    )
    domain = domain_result(
      'core', [entity('Author', 'authors'), entity('Membership', 'memberships'), entity('Team', 'teams')]
    )

    result = build(domain, 'Author' => owner_model(teams))

    expect(result.domains.first.relationships).to eq([])
    expect(result.diagnostics.map { |diagnostic| diagnostic.fetch('code') }).to eq(
      ['ASSOCIATION_SOURCE_UNRESOLVED']
    )
  end

  it 'stabilizes unreadable nested source lineage as source unresolved' do
    post_model = renderable_model('Post', 'posts')
    label_model = renderable_model('Label', 'labels')
    posts = association('posts', :has_many, klass: post_model)
    missing_inner_source = association(
      'labels', :has_many, through: true,
                           source_reflection: -> { raise ArgumentError, 'invalid inner source' }, klass: label_model
    )
    broken_options_source = belongs_to('label', klass: label_model)
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
    posts = association('posts', :has_many, klass: post_model)
    label_source = belongs_to('label', klass: label_model)
    scoped_hop = scope_only_reflection('labelings', labeling_model)
    unsafe_hop = association('BadName', :has_many, klass: labeling_model)
    outer = lambda do |name, hop|
      through_association(
        name, :has_many, through_reflection: posts, source_reflection: label_source, klass: label_model,
                         chain: [association(name, :has_many, klass: label_model), hop, posts]
      )
    end
    owner = owner_model(outer.call('scoped_labels', scoped_hop), outer.call('unsafe_labels', unsafe_hop))
    domain = domain_result(
      'core', [entity('Author', 'authors'), entity('Post', 'posts'),
               entity('Labeling', 'labelings'), entity('Label', 'labels')]
    )

    result = build(domain, 'Author' => owner)

    expect(result.diagnostics.map { |diagnostic| diagnostic.fetch('code') }).to eq(
      %w[ASSOCIATION_SCOPED_OMITTED ASSOCIATION_NAME_UNSUPPORTED_OMITTED]
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

  it 'reuses target and key omission diagnostics for ineligible direct has associations' do
    profile = renderable_model('Profile', 'profiles')
    author = owner_model(
      association('legacy_profiles', :has_many,
                  klass: renderable_model('LegacyProfile', 'legacy_profiles', renderable: false)),
      association('uuid_profiles', :has_many, klass: profile, foreign_key: 'author_id',
                                              active_record_primary_key: 'uuid'),
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
        ASSOCIATION_NON_PRIMARY_KEY_OMITTED
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
    post = owner_model(
      belongs_to('writer', klass: author_model, class_name: 'Author', foreign_key: 'author_id'),
      belongs_to('author', klass: author_model, foreign_key: 'author_id')
    )
    domain = domain_result(
      'core',
      [entity('Post', 'posts', columns: [column('id', false), column('author_id', true)]), entity('Author', 'authors')]
    )

    relationship = build(domain, 'Post' => post).domains.first.relationships.fetch(0)

    expect(relationship).to have_attributes(
      relationship_id: 'relationships/posts/author_id/authors/id', association_name: 'author'
    )
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

  def scope_only_reflection(name, model)
    reflection = Object.new
    reflection.define_singleton_method(:name) { name }
    reflection.define_singleton_method(:macro) { :has_many }
    reflection.define_singleton_method(:scope) { -> {} }
    reflection.define_singleton_method(:polymorphic?) { false }
    reflection.define_singleton_method(:klass) { model }
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

    def association_primary_key = @options.fetch(:association_primary_key, 'id')

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
