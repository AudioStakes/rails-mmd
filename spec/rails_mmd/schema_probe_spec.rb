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

  it 'keeps the selected physical base entity and normalizes direct and multi-level STI subtypes' do
    vehicle = sti_model('Vehicle', table_name: 'vehicles', sti_name: 'Vehicle')
    car = sti_model('Car', table_name: 'vehicles', base_class: vehicle, superclass_model: vehicle)
    sports_car = sti_model('SportsCar', table_name: 'vehicles', base_class: vehicle, superclass_model: car)
    models = {
      'Vehicle' => vehicle,
      'Car' => car,
      'SportsCar' => sports_car
    }
    domain = domain_result('core', [inventory_record('Vehicle', table_name: 'vehicles')])

    result = described_class.new(model_resolver: ->(name) { models.fetch(name) }).probe(
      domains: [domain],
      inventory_records: [
        inventory_record('Vehicle', table_name: 'vehicles'),
        inventory_record(
          'Car',
          base_class: 'Vehicle',
          table_name: 'vehicles',
          renderable: false,
          reason: 'sti_subclass'
        ),
        inventory_record('SportsCar', base_class: 'Vehicle', table_name: 'vehicles', renderable: false,
                                      reason: 'sti_subclass')
      ]
    )

    expect(result).to be_success
    expect(result.domains.first.entities.map(&:ruby_constant)).to eq(['Vehicle'])
    expect(result.domains.first.sti_subtypes).to match([
                                                         have_attributes(
                                                           entity_id: 'entities/vehicles/sti/Car',
                                                           base_entity_id: 'entities/vehicles',
                                                           parent_entity_id: 'entities/vehicles',
                                                           ruby_constant: 'Car',
                                                           table_name: 'vehicles',
                                                           inheritance_column: 'type',
                                                           sti_name: 'Car',
                                                           depth: 1
                                                         ),
                                                         have_attributes(
                                                           entity_id: 'entities/vehicles/sti/SportsCar',
                                                           base_entity_id: 'entities/vehicles',
                                                           parent_entity_id: 'entities/vehicles/sti/Car',
                                                           ruby_constant: 'SportsCar',
                                                           table_name: 'vehicles',
                                                           inheritance_column: 'type',
                                                           sti_name: 'SportsCar',
                                                           depth: 2
                                                         )
                                                       ])
  end

  it 'normalizes custom inheritance columns and keeps namespaced demodulized STI names distinct' do
    vehicle = sti_model('Vehicle', table_name: 'vehicles', inheritance_column: 'kind', sti_name: 'Vehicle')
    dealer_car = sti_model(
      'Dealer::Car',
      table_name: 'vehicles',
      base_class: vehicle,
      superclass_model: vehicle,
      inheritance_column: 'kind',
      sti_name: 'Car'
    )
    admin_car = sti_model(
      'Admin::Car',
      table_name: 'vehicles',
      base_class: vehicle,
      superclass_model: vehicle,
      inheritance_column: 'kind',
      sti_name: 'Car'
    )
    models = {
      'Vehicle' => vehicle,
      'Dealer::Car' => dealer_car,
      'Admin::Car' => admin_car
    }

    result = described_class.new(model_resolver: ->(name) { models.fetch(name) }).probe(
      domains: [domain_result('core', [inventory_record('Vehicle', table_name: 'vehicles')])],
      inventory_records: [
        inventory_record('Dealer::Car', base_class: 'Vehicle', table_name: 'vehicles', renderable: false,
                                        reason: 'sti_subclass'),
        inventory_record('Admin::Car', base_class: 'Vehicle', table_name: 'vehicles', renderable: false,
                                       reason: 'sti_subclass'),
        inventory_record('Vehicle', table_name: 'vehicles')
      ]
    )

    expect(result).to be_success
    expect(result.domains.first.sti_subtypes.map(&:entity_id)).to eq(
      %w[entities/vehicles/sti/Admin::Car entities/vehicles/sti/Dealer::Car]
    )
    expect(result.domains.first.sti_subtypes.map(&:inheritance_column)).to eq(%w[kind kind])
    expect(result.domains.first.sti_subtypes.map(&:sti_name)).to eq(%w[Car Car])
  end

  it 'treats an abstract boundary and false-positive or unreadable candidates as outside the selected STI family' do
    vehicle = sti_model('Vehicle', table_name: 'vehicles', sti_name: 'Vehicle')
    powered = sti_model(
      'Vehicle::Powered',
      table_name: 'vehicles',
      base_class: vehicle,
      superclass_model: vehicle,
      abstract_class: true
    )
    electric = sti_model('Vehicle::Electric', table_name: 'vehicles', superclass_model: powered)
    disabled = sti_model(
      'Vehicle::Disabled',
      table_name: 'vehicles',
      base_class: vehicle,
      superclass_model: vehicle,
      descends_from_active_record: true
    )
    no_column = sti_model(
      'Vehicle::NoColumn',
      table_name: 'vehicles',
      base_class: vehicle,
      superclass_model: vehicle,
      inheritance_column: nil
    )
    broken = sti_model(
      'Vehicle::Broken',
      table_name: 'vehicles',
      base_class: vehicle,
      superclass_model: vehicle,
      sti_name: -> { raise 'sti_name unavailable' }
    )
    models = {
      'Vehicle' => vehicle,
      'Vehicle::Powered' => powered,
      'Vehicle::Electric' => electric,
      'Vehicle::Disabled' => disabled,
      'Vehicle::NoColumn' => no_column,
      'Vehicle::Broken' => broken
    }

    result = described_class.new(model_resolver: ->(name) { models.fetch(name) }).probe(
      domains: [domain_result('core', [inventory_record('Vehicle', table_name: 'vehicles')])],
      inventory_records: [
        inventory_record('Vehicle', table_name: 'vehicles'),
        inventory_record('Vehicle::Powered', base_class: 'Vehicle', table_name: 'vehicles', renderable: false,
                                             reason: 'abstract_class'),
        inventory_record('Vehicle::Electric', base_class: 'Vehicle', table_name: 'vehicles', renderable: false,
                                              reason: 'sti_subclass'),
        inventory_record('Vehicle::Disabled', base_class: 'Vehicle', table_name: 'vehicles', renderable: false,
                                              reason: 'sti_subclass'),
        inventory_record('Vehicle::NoColumn', base_class: 'Vehicle', table_name: 'vehicles', renderable: false,
                                              reason: 'sti_subclass'),
        inventory_record('Vehicle::Broken', base_class: 'Vehicle', table_name: 'vehicles', renderable: false,
                                            reason: 'sti_subclass')
      ]
    )

    expect(result).to be_success
    expect(result.diagnostics).to eq([])
    expect(result.domains.first.sti_subtypes).to eq([])
  end

  it 'expands delegated-type families from explicit owners, caches expanded targets, and fences expanded owners' do
    delegated_runtime_file = '/gems/activerecord/lib/active_record/delegated_type.rb'
    install_delegated_type_runtime(delegated_runtime_file)

    entry = delegated_owner_model(
      delegated_runtime_file,
      'entryable',
      %w[Comment Blog::Post],
      columns: [
        column('id', :integer, false),
        column('entryable_id', :integer, true),
        column('entryable_type', :string, true)
      ]
    )
    message = delegated_owner_model(
      delegated_runtime_file,
      'subjectable',
      ['Comment'],
      columns: [
        column('id', :integer, false),
        column('subjectable_id', :integer, true),
        column('subjectable_type', :string, true)
      ]
    )

    comment_columns_reads = 0
    comment = model(
      table_exists: true,
      columns: lambda {
        comment_columns_reads += 1
        [column('id', :integer, false)]
      }
    )
    commentable_reflection = polymorphic_reflection(:commentable)
    comment_labels_reflection = habtm_reflection('comment_labels')
    comment.define_singleton_method(:reflect_on_all_associations) do |macro = nil|
      reflections = [commentable_reflection, comment_labels_reflection]
      macro ? reflections.select { |reflection| reflection.macro == macro } : reflections
    end
    define_generated_types_method(comment, :commentable_types, delegated_runtime_file, ['NestedComment'])

    blog_post = model(table_exists: true, columns: [column('id', :integer, false)])
    models = {
      'Entry' => entry,
      'Message' => message,
      'Comment' => comment,
      'Blog::Post' => blog_post
    }

    result = described_class.new(model_resolver: ->(name) { models.fetch(name) }).probe(
      domains: [
        domain_result(
          'core',
          [
            inventory_record('Entry', table_name: 'entries'),
            inventory_record('Message', table_name: 'messages')
          ]
        )
      ],
      inventory_records: [
        inventory_record('Entry', table_name: 'entries'),
        inventory_record('Message', table_name: 'messages'),
        inventory_record('Comment', table_name: 'comments'),
        inventory_record('Blog::Post', table_name: 'blog_posts'),
        inventory_record('NestedComment', base_class: 'Comment', table_name: 'comments', renderable: false,
                                          reason: 'sti_subclass')
      ]
    )

    expect(result).to be_success
    expect(result.diagnostics).to eq([])
    expect(result.domains.first.entities.map(&:ruby_constant)).to eq(%w[Entry Message Blog::Post Comment])
    expect(result.domains.first.entities.select do |entity|
      entity.selection_origin == :delegated_type_expanded
    end.map(&:ruby_constant)).to eq(%w[Blog::Post Comment])
    expect(result.domains.first.delegated_type_families.map do |family|
      [
        family.owner_entity_id,
        family.owner_ruby_constant,
        family.association_name,
        family.foreign_key,
        family.foreign_type,
        family.scoped,
        family.root_diagnostic_code,
        family.targets.map do |target|
          [target.ruby_constant, target.entity_id, target.status, target.diagnostic_code]
        end
      ]
    end).to eq([
                 [
                   'entities/entries',
                   'Entry',
                   'entryable',
                   'entryable_id',
                   'entryable_type',
                   false,
                   nil,
                   [
                     ['Blog::Post', 'entities/blog_posts', :expanded, nil],
                     ['Comment', 'entities/comments', :expanded, nil]
                   ]
                 ],
                 [
                   'entities/messages',
                   'Message',
                   'subjectable',
                   'subjectable_id',
                   'subjectable_type',
                   false,
                   nil,
                   [['Comment', 'entities/comments', :expanded, nil]]
                 ]
               ])
    expect(result.domains.first.join_tables).to eq([])
    expect(result.domains.first.sti_subtypes).to eq([])
    expect(comment_columns_reads).to eq(2)
  end

  it 'rejects spoofed delegated-type discovery when the generated method provenance does not match runtime' do
    install_delegated_type_runtime('/gems/activerecord/lib/active_record/delegated_type.rb')

    spoof_called = false
    entry = model(
      table_exists: true,
      columns: [
        column('id', :integer, false),
        column('entryable_id', :integer, true),
        column('entryable_type', :string, true)
      ]
    )
    entryable_reflection = polymorphic_reflection(:entryable)
    entry.define_singleton_method(:reflect_on_all_associations) { |_macro = nil| [entryable_reflection] }
    entry.define_singleton_method(:entryable_types) do
      spoof_called = true
      raise 'spoofed application method must not be called'
    end

    result = described_class.new(model_resolver: ->(_name) { entry }).probe(
      domains: [domain_result('core', [record('Entry')])],
      inventory_records: [inventory_record('Entry', table_name: 'entries')]
    )

    expect(result).to be_success
    expect(result.diagnostics).to eq([])
    expect(result.domains.first.delegated_type_families).to eq([])
    expect(spoof_called).to be(false)
  end

  it 'contains missing, raising, and unavailable delegated-type discovery methods' do
    delegated_runtime_file = '/gems/activerecord/lib/active_record/delegated_type.rb'
    columns = [column('id', :integer, false), column('entryable_id', :integer, true),
               column('entryable_type', :string, true)]

    install_delegated_type_runtime(delegated_runtime_file)
    missing_method_owner = model(table_exists: true, columns: columns)
    reflection = polymorphic_reflection('entryable')
    missing_method_owner.define_singleton_method(:reflect_on_all_associations) { [reflection] }
    missing_result = described_class.new(model_resolver: ->(_) { missing_method_owner }).probe(
      domains: [domain_result('core', [record('MissingMethodOwner')])],
      inventory_records: [inventory_record('MissingMethodOwner')]
    )

    raising_owner = delegated_owner_model(
      delegated_runtime_file, 'entryable', ['Target'], columns: columns
    )
    # rubocop:disable Style/EvalWithLocation
    raising_owner.singleton_class.class_eval(<<~RUBY, delegated_runtime_file, 1)
      define_method(:entryable_types) { raise 'types unavailable' }
    RUBY
    # rubocop:enable Style/EvalWithLocation
    raising_result = described_class.new(model_resolver: ->(_) { raising_owner }).probe(
      domains: [domain_result('core', [record('RaisingOwner')])],
      inventory_records: [inventory_record('RaisingOwner')]
    )

    unavailable_runtime = Module.new
    unavailable_runtime.define_singleton_method(:instance_method) { |_| raise 'runtime source unavailable' }
    active_record = Module.new
    active_record.const_set(:DelegatedType, unavailable_runtime)
    stub_const('ActiveRecord', active_record)
    unavailable_result = described_class.new(model_resolver: ->(_) { missing_method_owner }).probe(
      domains: [domain_result('core', [record('UnavailableRuntimeOwner')])],
      inventory_records: [inventory_record('UnavailableRuntimeOwner')]
    )

    expect([missing_result, raising_result, unavailable_result].map do |result|
      result.domains.first.delegated_type_families
    end).to eq([[], [], []])
  end

  it 'normalizes delegated targets across exclusion, ownership, connection, renderability, and failed expansion' do
    delegated_runtime_file = '/gems/activerecord/lib/active_record/delegated_type.rb'
    install_delegated_type_runtime(delegated_runtime_file)

    entry = delegated_owner_model(
      delegated_runtime_file,
      'entryable',
      %w[
        Expanded
        Excluded
        Selected
        SelectedBroken
        Broken
        Missing
        OtherConnection
        OtherDomain
        StiLeaf
      ],
      columns: [
        column('id', :integer, false),
        column('entryable_id', :integer, true),
        column('entryable_type', :string, true)
      ]
    )
    selected = model(table_exists: true, columns: [column('id', :integer, false)])
    selected_broken = model(table_exists: false)
    expanded = model(table_exists: true, columns: [column('id', :integer, false)])
    broken = model(table_exists: false)
    models = {
      'Entry' => entry,
      'Selected' => selected,
      'SelectedBroken' => selected_broken,
      'Expanded' => expanded,
      'Broken' => broken
    }

    result = described_class.new(model_resolver: ->(name) { models.fetch(name) }).probe(
      domains: [
        domain_result(
          'core',
          [
            inventory_record('Entry', table_name: 'entries'),
            inventory_record('Selected', table_name: 'selecteds'),
            inventory_record('SelectedBroken', table_name: 'selected_brokens')
          ],
          excluded_ruby_constants: ['Excluded']
        )
      ],
      inventory_records: [
        inventory_record('Entry', table_name: 'entries'),
        inventory_record('Selected', table_name: 'selecteds'),
        inventory_record('SelectedBroken', table_name: 'selected_brokens'),
        inventory_record('Expanded', table_name: 'expandeds'),
        inventory_record('Broken', table_name: 'brokens'),
        inventory_record(
          'OtherConnection',
          table_name: 'other_connections',
          connection_context_id: '{"name":"replica","role":"reading","shard":"default"}'
        ),
        inventory_record('OtherDomain', table_name: 'other_domains'),
        inventory_record('StiLeaf', table_name: 'selecteds', renderable: false, reason: 'sti_subclass')
      ],
      owned_domain_ids_by_constant: { 'OtherDomain' => ['billing'] }
    )

    family = result.domains.first.delegated_type_families.fetch(0)

    expect(result).not_to be_success
    expect(result.exit_code).to eq(2)
    expect(result.diagnostics).to include(
      include(
        'code' => 'MODEL_TABLE_MISSING',
        'metadata' => include('ruby_constant' => 'Broken')
      )
    )
    expect(result.domains.first.entities.map(&:ruby_constant)).to eq(%w[Entry Selected Expanded])
    expect(result.domains.first.entities.find { |entity| entity.ruby_constant == 'Expanded' }.selection_origin).to eq(
      :delegated_type_expanded
    )
    expect(family.owner_entity_id).to eq('entities/entries')
    expect(family.owner_ruby_constant).to eq('Entry')
    expect(family.association_name).to eq('entryable')
    expect(family.root_diagnostic_code).to be_nil
    expect(family.targets).to match([
                                      have_attributes(
                                        ruby_constant: 'Broken',
                                        entity_id: nil,
                                        status: :not_renderable,
                                        diagnostic_code: 'ASSOCIATION_TARGET_NOT_RENDERABLE_OMITTED'
                                      ),
                                      have_attributes(
                                        ruby_constant: 'Excluded',
                                        entity_id: nil,
                                        status: :excluded,
                                        diagnostic_code: 'DOMAIN_RELATIONSHIP_OMITTED'
                                      ),
                                      have_attributes(
                                        ruby_constant: 'Expanded',
                                        entity_id: 'entities/expandeds',
                                        status: :expanded,
                                        diagnostic_code: nil
                                      ),
                                      have_attributes(
                                        ruby_constant: 'Missing',
                                        entity_id: nil,
                                        status: :unresolved,
                                        diagnostic_code: 'ASSOCIATION_TARGET_UNRESOLVED'
                                      ),
                                      have_attributes(
                                        ruby_constant: 'OtherConnection',
                                        entity_id: nil,
                                        status: :other_connection,
                                        diagnostic_code: 'DOMAIN_RELATIONSHIP_OMITTED'
                                      ),
                                      have_attributes(
                                        ruby_constant: 'OtherDomain',
                                        entity_id: nil,
                                        status: :other_domain,
                                        diagnostic_code: 'DOMAIN_RELATIONSHIP_OMITTED'
                                      ),
                                      have_attributes(
                                        ruby_constant: 'Selected',
                                        entity_id: 'entities/selecteds',
                                        status: :selected,
                                        diagnostic_code: nil
                                      ),
                                      have_attributes(
                                        ruby_constant: 'SelectedBroken',
                                        entity_id: nil,
                                        status: :not_renderable,
                                        diagnostic_code: 'ASSOCIATION_TARGET_NOT_RENDERABLE_OMITTED'
                                      ),
                                      have_attributes(
                                        ruby_constant: 'StiLeaf',
                                        entity_id: nil,
                                        status: :not_renderable,
                                        diagnostic_code: 'ASSOCIATION_TARGET_NOT_RENDERABLE_OMITTED'
                                      )
                                    ])
  end

  it 'orders failed delegated expansions independently of selected owner order' do
    delegated_runtime_file = '/gems/activerecord/lib/active_record/delegated_type.rb'
    install_delegated_type_runtime(delegated_runtime_file)
    columns = [column('id', :integer, false), column('entryable_id', :integer, true),
               column('entryable_type', :string, true)]
    models = {
      'AOwner' => delegated_owner_model(delegated_runtime_file, 'entryable', ['ABroken'], columns: columns),
      'ZOwner' => delegated_owner_model(delegated_runtime_file, 'entryable', ['ZBroken'], columns: columns),
      'ABroken' => model(table_exists: false),
      'ZBroken' => model(table_exists: false)
    }
    inventory = [
      inventory_record('AOwner'), inventory_record('ZOwner'),
      inventory_record('ABroken'), inventory_record('ZBroken')
    ]
    probe = described_class.new(model_resolver: ->(name) { models.fetch(name) })

    diagnostics_for = lambda do |owner_names|
      result = probe.probe(
        domains: [domain_result('core', owner_names.map { |name| record(name) })],
        inventory_records: inventory
      )
      result.diagnostics.map { |diagnostic| diagnostic.dig('metadata', 'ruby_constant') }
    end

    expect(diagnostics_for.call(%w[ZOwner AOwner])).to eq(%w[ABroken ZBroken])
    expect(diagnostics_for.call(%w[AOwner ZOwner])).to eq(%w[ABroken ZBroken])
  end

  it 'records delegated root preflight omissions without probing targets' do
    delegated_runtime_file = '/gems/activerecord/lib/active_record/delegated_type.rb'
    install_delegated_type_runtime(delegated_runtime_file)

    target = model(
      table_exists: -> { raise 'delegated target should not be probed when root eligibility fails' },
      columns: -> { raise 'delegated target should not be probed when root eligibility fails' }
    )
    models = {
      'BadNameOwner' => delegated_owner_model(
        delegated_runtime_file,
        'entryable::bad',
        ['Comment'],
        columns: [column('id', :integer, false), column('entryable_id', :integer, true),
                  column('entryable_type', :string, true)]
      ),
      'CompositeOwner' => delegated_owner_model(
        delegated_runtime_file,
        'entryable',
        ['Comment'],
        columns: [column('id', :integer, false), column('entryable_id', :integer, true),
                  column('entryable_type', :string, true)],
        foreign_key: %w[entryable_id tenant_id]
      ),
      'CustomKeyOwner' => delegated_owner_model(
        delegated_runtime_file,
        'entryable',
        ['Comment'],
        columns: [column('id', :integer, false), column('entryable_id', :integer, true),
                  column('entryable_type', :string, true)],
        foreign_key: 'custom_entryable_id',
        foreign_type: 'custom_entryable_type'
      ),
      'PrimaryKeyOwner' => delegated_owner_model(
        delegated_runtime_file,
        'entryable',
        ['Comment'],
        columns: [column('id', :integer, false), column('entryable_id', :integer, true),
                  column('entryable_type', :string, true)],
        active_record_primary_key: 'slug',
        options: { primary_key: 'slug' }
      ),
      'MissingColumnOwner' => delegated_owner_model(
        delegated_runtime_file,
        'entryable',
        ['Comment'],
        columns: [column('id', :integer, false), column('entryable_id', :integer, true)]
      ),
      'Comment' => target
    }

    result = described_class.new(model_resolver: ->(name) { models.fetch(name) }).probe(
      domains: [
        domain_result(
          'core',
          %w[BadNameOwner CompositeOwner CustomKeyOwner PrimaryKeyOwner MissingColumnOwner].map { |name| record(name) }
        )
      ],
      inventory_records: [
        inventory_record('BadNameOwner', table_name: 'bad_name_owners'),
        inventory_record('CompositeOwner', table_name: 'composite_owners'),
        inventory_record('CustomKeyOwner', table_name: 'custom_key_owners'),
        inventory_record('PrimaryKeyOwner', table_name: 'primary_key_owners'),
        inventory_record('MissingColumnOwner', table_name: 'missing_column_owners'),
        inventory_record('Comment', table_name: 'comments')
      ]
    )

    expect(result).to be_success
    expect(result.diagnostics).to eq([])
    expect(result.domains.first.entities.map(&:ruby_constant)).to eq(
      %w[BadNameOwner CompositeOwner CustomKeyOwner PrimaryKeyOwner MissingColumnOwner]
    )
    expect(result.domains.first.delegated_type_families.map do |family|
      [family.owner_ruby_constant, family.association_name, family.root_diagnostic_code, family.targets]
    end).to eq([
                 ['BadNameOwner', 'entryable::bad', 'ASSOCIATION_NAME_UNSUPPORTED_OMITTED', []],
                 ['CompositeOwner', 'entryable', 'ASSOCIATION_COMPOSITE_KEY_OMITTED', []],
                 ['CustomKeyOwner', 'entryable', 'ASSOCIATION_POLYMORPHIC_OMITTED', []],
                 ['MissingColumnOwner', 'entryable', 'ASSOCIATION_KEY_COLUMN_MISSING', []],
                 ['PrimaryKeyOwner', 'entryable', 'ASSOCIATION_NON_PRIMARY_KEY_OMITTED', []]
               ])
  end

  it 'caches hidden HABTM join-table metadata for selected public reflections' do
    reflection = Struct.new(:macro, :join_table).new(:has_and_belongs_to_many, 'authors_tags')
    connection = Object.new
    join_columns = [column('author_id', :integer, false), column('tag_id', :integer, false)]
    connection.define_singleton_method(:data_source_exists?) { |name| name == 'authors_tags' }
    connection.define_singleton_method(:columns) { |_name| join_columns }
    connection.define_singleton_method(:primary_key) { |_name| nil }
    author = model(table_exists: true, columns: [column('id', :integer, false)])
    author.define_singleton_method(:reflect_on_all_associations) do |macro = nil|
      macro == :has_and_belongs_to_many ? [reflection] : []
    end
    author.define_singleton_method(:connection) { connection }

    result = described_class.new(model_resolver: ->(_name) { author }).probe(
      domains: [domain_result('core', [record('Author')])]
    )

    expect(result.domains.first.join_tables).to contain_exactly(
      have_attributes(table_name: 'authors_tags', primary_key: nil)
    )
    expect(result.domains.first.join_tables.first.columns.map(&:name)).to eq(%w[author_id tag_id])
  end

  it 'contains HABTM reflection and join-table connection failures' do
    reflection = Struct.new(:macro, :join_table).new(:has_and_belongs_to_many, 'authors_tags')
    reflection_error = model(table_exists: true, columns: [column('id', :integer, false)])
    reflection_error.define_singleton_method(:reflect_on_all_associations) { |_macro| raise 'reflection unavailable' }

    connection_error = model(table_exists: true, columns: [column('id', :integer, false)])
    connection_error.define_singleton_method(:reflect_on_all_associations) { |_macro| [reflection] }
    denied_connection = Object.new
    denied_connection.define_singleton_method(:data_source_exists?) { |_name| raise 'connection denied' }
    connection_error.define_singleton_method(:connection) { denied_connection }

    columns_error = model(table_exists: true, columns: [column('id', :integer, false)])
    columns_reflection = Struct.new(:macro, :join_table).new(
      :has_and_belongs_to_many,
      'authors_tags_broken'
    )
    columns_error.define_singleton_method(:reflect_on_all_associations) { |_macro| [columns_reflection] }
    broken_connection = Object.new
    broken_connection.define_singleton_method(:data_source_exists?) { |_name| true }
    broken_connection.define_singleton_method(:columns) { |_name| raise 'columns unavailable' }
    broken_connection.define_singleton_method(:primary_key) { |_name| nil }
    columns_error.define_singleton_method(:connection) { broken_connection }
    models = {
      'ReflectionError' => reflection_error,
      'ConnectionError' => connection_error,
      'ColumnsError' => columns_error
    }

    result = described_class.new(model_resolver: ->(name) { models.fetch(name) }).probe(
      domains: [domain_result('core', models.keys.map { |name| record(name) })]
    )

    expect(result).to be_success
    expect(result.domains.first.join_tables).to eq([])
  end

  it 'retries a shared HABTM join table through another validated entity model' do
    reflection = Struct.new(:macro, :join_table).new(:has_and_belongs_to_many, 'authors_tags')
    denied = model(table_exists: true, columns: [column('id', :integer, false)])
    denied.define_singleton_method(:reflect_on_all_associations) { |_macro| [reflection] }
    denied.define_singleton_method(:connection) { raise 'connection denied' }

    readable = model(table_exists: true, columns: [column('id', :integer, false)])
    readable.define_singleton_method(:reflect_on_all_associations) { |_macro| [reflection] }
    join_columns = [column('author_id', :integer, false), column('tag_id', :integer, false)]
    connection = Object.new
    connection.define_singleton_method(:data_source_exists?) { |_name| true }
    connection.define_singleton_method(:columns) { |_name| join_columns }
    connection.define_singleton_method(:primary_key) { |_name| nil }
    readable.define_singleton_method(:connection) { connection }
    models = { 'Author' => denied, 'Tag' => readable }

    result = described_class.new(model_resolver: ->(name) { models.fetch(name) }).probe(
      domains: [domain_result('core', models.keys.map { |name| record(name) })]
    )

    expect(result.domains.first.join_tables).to contain_exactly(
      have_attributes(table_name: 'authors_tags', primary_key: nil)
    )
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

  # rubocop:disable Metrics/MethodLength
  def domain_result(domain_id, records, excluded_ruby_constants: [])
    domain_result_class = if RailsMmd::DomainResolver::DomainResult.members.include?(:excluded_ruby_constants)
                            RailsMmd::DomainResolver::DomainResult
                          else
                            Struct.new(:domain_id, :records, :diagnostics, :excluded_ruby_constants, keyword_init: true)
                          end

    domain_result_class.new(
      domain_id: domain_id,
      records: records,
      diagnostics: [],
      excluded_ruby_constants: excluded_ruby_constants
    )
  end
  # rubocop:enable Metrics/MethodLength

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

  # rubocop:disable Metrics/MethodLength
  def inventory_record(ruby_constant, **overrides)
    defaults = {
      abstract_class: false,
      base_class: ruby_constant,
      table_name: "#{ruby_constant.downcase}s",
      connection_context_id: '{"name":"primary","role":"writing","shard":"default"}',
      renderable: true,
      renderability_reason: nil
    }
    attributes = defaults.merge(overrides)
    attributes[:renderability_reason] = attributes.delete(:reason) if attributes.key?(:reason)
    attributes[:abstract_class] = attributes[:renderability_reason] == 'abstract_class'

    RailsMmd::ModelInventory::Record.new(
      ruby_constant: ruby_constant,
      abstract_class: attributes.fetch(:abstract_class),
      base_class: attributes.fetch(:base_class),
      table_name: attributes.fetch(:table_name),
      connection_context_id: attributes.fetch(:connection_context_id),
      renderable: attributes.fetch(:renderable),
      renderability_reason: attributes.fetch(:renderability_reason)
    )
  end
  # rubocop:enable Metrics/MethodLength

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
      define_singleton_method(:reflect_on_all_associations) do |macro = nil|
        macro ? reflections.select { |reflection| reflection.macro == macro } : reflections
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

  # rubocop:disable Style/EvalWithLocation
  def install_delegated_type_runtime(source_file)
    delegated_type_module = Module.new
    delegated_type_module.module_eval(<<~RUBY, source_file, 1)
      def delegated_type(*)
      end
    RUBY
    active_record = Module.new
    active_record.const_set(:DelegatedType, delegated_type_module)
    stub_const('ActiveRecord', active_record)
  end
  # rubocop:enable Style/EvalWithLocation

  # rubocop:disable Metrics/MethodLength, Metrics/ParameterLists
  def delegated_owner_model(
    source_file,
    association_name,
    types,
    columns:,
    foreign_key: "#{association_name}_id",
    foreign_type: "#{association_name}_type",
    active_record_primary_key: nil,
    scope: nil,
    options: {}
  )
    owner = model(table_exists: true, columns: columns)
    reflection = polymorphic_reflection(
      association_name,
      foreign_key: foreign_key,
      foreign_type: foreign_type,
      active_record_primary_key: active_record_primary_key,
      scope: scope,
      options: options
    )
    owner.define_singleton_method(:reflect_on_all_associations) do |macro = nil|
      macro ? [reflection].select { |candidate| candidate.macro == macro } : [reflection]
    end
    define_generated_types_method(owner, "#{association_name}_types", source_file, types)
    owner
  end
  # rubocop:enable Metrics/MethodLength, Metrics/ParameterLists

  # rubocop:disable Style/DocumentDynamicEvalDefinition, Style/EvalWithLocation
  def define_generated_types_method(model_class, method_name, source_file, values)
    serialized_values = values.map(&:to_s).inspect
    model_class.singleton_class.class_eval(<<~RUBY, source_file, 1)
      define_method(#{method_name.to_sym.inspect}) do
        #{serialized_values}
      end
    RUBY
  end
  # rubocop:enable Style/DocumentDynamicEvalDefinition, Style/EvalWithLocation

  # rubocop:disable Metrics/ParameterLists
  def polymorphic_reflection(
    name,
    foreign_key: "#{name}_id",
    foreign_type: "#{name}_type",
    active_record_primary_key: nil,
    scope: nil,
    options: {}
  )
    Struct.new(:name, :macro, :foreign_key, :foreign_type, :active_record_primary_key, :scope, :options) do
      def polymorphic? = true
    end.new(name, :belongs_to, foreign_key, foreign_type, active_record_primary_key, scope, options)
  end
  # rubocop:enable Metrics/ParameterLists

  def habtm_reflection(join_table)
    Struct.new(:macro, :join_table).new(:has_and_belongs_to_many, join_table)
  end

  def define_db_config(model, database)
    model.define_singleton_method(:connection_db_config) do
      Struct.new(:name, :adapter, :database, :host, :port, :username).new(
        'primary', 'sqlite3', database, nil, nil, nil
      )
    end
  end

  # rubocop:disable Metrics/AbcSize, Metrics/MethodLength
  def sti_model(ruby_constant, **options)
    inheritance_column = options.fetch(:inheritance_column, 'type')
    columns = options.fetch(:columns) do
      [column('id', :integer, false), column(inheritance_column, :string, true)]
    end

    model(table_exists: true, columns: columns).tap do |model_class|
      model_class.define_singleton_method(:name) { ruby_constant }
      model_class.define_singleton_method(:table_name) { options.fetch(:table_name) }
      model_class.define_singleton_method(:base_class) { options.fetch(:base_class, model_class) }
      model_class.define_singleton_method(:superclass) { options.fetch(:superclass_model, Object) }
      model_class.define_singleton_method(:inheritance_column) { model_class.callable_value(inheritance_column) }
      model_class.define_singleton_method(:descends_from_active_record?) do
        model_class.callable_value(options.fetch(:descends_from_active_record, false))
      end
      model_class.define_singleton_method(:abstract_class?) do
        model_class.callable_value(options.fetch(:abstract_class, false))
      end
      model_class.define_singleton_method(:sti_name) do
        model_class.callable_value(options.fetch(:sti_name, ruby_constant.split('::').last))
      end
    end
  end
  # rubocop:enable Metrics/AbcSize, Metrics/MethodLength

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
