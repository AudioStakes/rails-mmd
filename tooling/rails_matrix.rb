# frozen_string_literal: true

require 'bundler'
require 'fileutils'
require 'json'
require 'open3'
require 'pathname'
require 'tmpdir'
require 'yaml'
require 'rails_mmd/mermaid_serializer'
require 'rails_mmd/relationship_id_codec'
require 'rails_mmd/schema_validator'

module RailsMatrix
  class PrerequisiteError < StandardError; end
  class VerificationError < StandardError; end

  Pair = Data.define(:ruby_version, :rails_series) do
    def name
      "ruby-#{ruby_version}-rails-#{rails_series}"
    end
  end

  FAMILY_RUNTIME_ORACLES = {
    'delegated_type' => {
      command: %w[exec ruby bin/rails runner script/rails_mmd_delegated_type_runtime_oracle.rb],
      actual: 'delegated_type_runtime.json',
      expected: 'rails_mmd_expected_delegated_type_runtime.json',
      label: 'delegated type'
    },
    'composite_keys' => {
      command: %w[exec ruby bin/rails runner script/rails_mmd_composite_runtime_oracle.rb],
      actual: 'composite_runtime.json',
      expected: 'rails_mmd_expected_composite_runtime.json',
      label: 'composite key'
    },
    'specialized_options' => {
      command: %w[exec ruby bin/rails runner script/rails_mmd_specialized_options_runtime_oracle.rb],
      actual: 'specialized_options_runtime.json',
      expected: 'rails_mmd_expected_specialized_options_runtime.json',
      label: 'specialized options'
    },
    'association_behavior' => {
      command: %w[exec ruby bin/rails runner script/rails_mmd_association_behavior_runtime_oracle.rb],
      actual: 'association_behavior_runtime.json',
      expected: 'rails_mmd_expected_association_behavior_runtime.json',
      label: 'association behavior'
    },
    'cross_domain_multi_db' => {
      command: %w[exec ruby bin/rails runner script/rails_mmd_cross_domain_runtime_oracle.rb],
      actual: 'cross_domain_runtime.json',
      expected: 'rails_mmd_expected_cross_domain_runtime.json',
      label: 'cross-domain multi-DB'
    }
  }.freeze

  PAIR_PROBES = {
    'composite_keys' => {
      script: 'docs/p2/04-composite-keys/probes/composite_habtm_probe.rb',
      label: 'composite HABTM'
    },
    'association_behavior' => {
      script: 'docs/p2/07-association-behavior-metadata/probes/behavior_options_probe.rb',
      label: 'association behavior options'
    },
    'cross_domain_multi_db' => {
      script: 'docs/p2/06-cross-domain-multi-db/probes/connection_boundary_probe.rb',
      label: 'connection boundary'
    }
  }.freeze

  LOCKED_RAILS_VERSIONS = {
    '7.2' => '7.2.3.1',
    '8.1' => '8.1.3'
  }.freeze

  COMPOSITE_HABTM_EXPECTATIONS = {
    'book_sql_has_full_owner_tuple' => false,
    'book_sql_uses_scalar_fallback' => true,
    'author_sql_has_full_owner_tuple' => false,
    'author_sql_uses_scalar_fallback' => true
  }.freeze

  # Validates the P2-07 probe against a closed semantic projection.
  class AssociationBehaviorProbeValidator
    EXPECTATIONS = {
      'direct.belongs_to.proposed_public_declaration.association_name' => 'account',
      'direct.belongs_to.proposed_public_declaration.association_macro' => 'belongs_to',
      'direct.belongs_to.proposed_public_declaration.dependent.action' => 'delete',
      'direct.belongs_to.proposed_public_declaration.dependent.target' => 'associated_records',
      'direct.belongs_to.proposed_public_declaration.touch.attribute' => 'members_touched_at',
      'direct.belongs_to.proposed_public_declaration.counter_cache.column' => 'p207_members_count',
      'direct.belongs_to.proposed_public_declaration.counter_cache.active' => true,
      'direct.belongs_to_inactive_custom_counter.proposed_public_declaration.counter_cache.column' =>
      'custom_members_count',
      'direct.belongs_to_inactive_custom_counter.proposed_public_declaration.counter_cache.active' => false,
      'direct.belongs_to_inactive_custom_counter.proposed_public_declaration.association_name' => 'custom_account',
      'direct.belongs_to_inactive_custom_counter.proposed_public_declaration.association_macro' => 'belongs_to',
      'direct.has_many.proposed_public_declaration.association_name' => 'members',
      'direct.has_many.proposed_public_declaration.association_macro' => 'has_many',
      'direct.has_many.proposed_public_declaration.dependent.action' => 'destroy',
      'direct.has_many.proposed_public_declaration.dependent.target' => 'associated_records',
      'direct.has_one.proposed_public_declaration.association_name' => 'profile',
      'direct.has_one.proposed_public_declaration.association_macro' => 'has_one',
      'direct.has_one.proposed_public_declaration.dependent.action' => 'nullify',
      'direct.has_one.proposed_public_declaration.dependent.target' => 'associated_records',
      'direct.has_one.proposed_public_declaration.touch.attribute' => 'profile_touched_at',
      'through.has_many.proposed_public_declaration.association_name' => 'notes',
      'through.has_many.proposed_public_declaration.association_macro' => 'has_many',
      'through.has_many.proposed_public_declaration.dependent.action' => 'delete_all',
      'through.has_many.proposed_public_declaration.dependent.target' => 'through_records',
      'through.has_one.proposed_public_declaration.association_name' => 'latest_note',
      'through.has_one.proposed_public_declaration.association_macro' => 'has_one',
      'through.has_one.proposed_public_declaration.touch.attribute' => 'latest_note_touched_at',
      'polymorphic.root.proposed_public_declaration.association_name' => 'attachable',
      'polymorphic.root.proposed_public_declaration.association_macro' => 'belongs_to',
      'polymorphic.root.proposed_public_declaration.dependent.action' => 'destroy',
      'polymorphic.root.proposed_public_declaration.dependent.target' => 'associated_records',
      'polymorphic.root.proposed_public_declaration.touch.attribute' => nil,
      'polymorphic.root.proposed_public_declaration.counter_cache.column' => 'attachments_count',
      'polymorphic.root.proposed_public_declaration.counter_cache.active' => true,
      'polymorphic.inverse.proposed_public_declaration.association_name' => 'attachments',
      'polymorphic.inverse.proposed_public_declaration.association_macro' => 'has_many',
      'polymorphic.inverse.proposed_public_declaration.dependent.action' => 'nullify',
      'polymorphic.inverse.proposed_public_declaration.dependent.target' => 'associated_records',
      'delegated_type.root.proposed_public_declaration.association_name' => 'entryable',
      'delegated_type.root.proposed_public_declaration.association_macro' => 'belongs_to',
      'delegated_type.root.proposed_public_declaration.dependent.action' => 'destroy',
      'delegated_type.root.proposed_public_declaration.dependent.target' => 'associated_records',
      'delegated_type.root.proposed_public_declaration.touch.attribute' => nil,
      'delegated_type.root.proposed_public_declaration.counter_cache.column' => 'entries_count',
      'delegated_type.root.proposed_public_declaration.counter_cache.active' => true,
      'delegated_type.inverse.proposed_public_declaration.association_name' => 'entry',
      'delegated_type.inverse.proposed_public_declaration.association_macro' => 'has_one',
      'delegated_type.inverse.proposed_public_declaration.dependent.action' => 'nullify',
      'delegated_type.inverse.proposed_public_declaration.dependent.target' => 'associated_records',
      'inverse_counter_naming_only.has_many.proposed_public_declaration' => nil,
      'inverse_counter_naming_only.belongs_to.proposed_public_declaration' => nil,
      'inverse_counter_naming_only.belongs_to.options.counter_cache' => nil,
      'habtm.proposed_public_declaration' => nil
    }.freeze

    def validate(payload, pair)
      validate_rails_version(payload, pair)
      actual = projection(payload)
      return if actual == EXPECTATIONS

      raise VerificationError,
            "#{pair.name} association behavior options probe did not match expectation\n" \
            "expected: #{JSON.generate(EXPECTATIONS)}\nactual: #{JSON.generate(actual)}"
    rescue KeyError, TypeError, NoMethodError
      raise VerificationError, "#{pair.name} association behavior options probe did not match expectation"
    end

    private

    def validate_rails_version(payload, pair)
      expected = LOCKED_RAILS_VERSIONS.fetch(pair.rails_series)
      return if payload.fetch('rails_version') == expected

      raise VerificationError, "#{pair.name} association behavior probe did not match expectation"
    end

    def projection(payload)
      EXPECTATIONS.to_h { |key, _value| [key, payload.dig(*key.split('.'))] }
    end
  end

  # Validates the checked-in P2-06 probe without snapshotting temporary paths.
  class ConnectionBoundaryProbeValidator
    def validate(payload, pair)
      primary_database, archive_database, reading_database = databases(payload)
      expected = expected_payload(pair, primary_database, archive_database, reading_database)
      return if valid_payload?(payload, expected, primary_database, archive_database, reading_database)

      raise VerificationError,
            "#{pair.name} connection boundary probe did not match expectation\n" \
            "expected: #{JSON.generate(expected)}\nactual: #{JSON.generate(payload)}"
    rescue KeyError, NoMethodError => e
      raise VerificationError, "#{pair.name} published invalid connection boundary probe: #{e.message}"
    end

    private

    def databases(payload)
      contexts = payload.fetch('contexts')
      %w[primary archive reading].map { |name| context_database(contexts, name) }
    end

    def valid_payload?(payload, expected, primary_database, archive_database, reading_database)
      primary_database == reading_database && primary_database != archive_database && payload == expected
    end

    def context_database(contexts, name)
      database = contexts.fetch(name).fetch('database')
      raise KeyError, "#{name}.database must be a non-empty string" unless database.is_a?(String) && !database.empty?

      database
    end

    def expected_payload(pair, primary_database, archive_database, reading_database)
      {
        'rails_version' => LOCKED_RAILS_VERSIONS.fetch(pair.rails_series),
        'reflections' => expected_reflections,
        'contexts' => expected_contexts(primary_database, archive_database, reading_database),
        'database_evidence' => {
          'primary_foreign_keys_for_archive_table' => 0,
          'archive_foreign_keys_for_owner_table' => 0
        },
        'identity_collision' => { 'same_table_name' => true, 'different_context_name' => true }
      }
    end

    def expected_reflections
      {
        'belongs_to' => {
          'klass' => 'P206Account', 'foreign_key' => 'account_id', 'association_primary_key' => 'id'
        },
        'has_many' => {
          'klass' => 'P206Audit', 'foreign_key' => 'account_id', 'association_primary_key' => 'id'
        }
      }
    end

    def expected_contexts(primary_database, archive_database, reading_database)
      {
        'primary' => context('primary', 'writing', primary_database),
        'archive' => context('archive', 'writing', archive_database),
        'reading' => context('primary_replica', 'reading', reading_database),
        'primary_vs_archive_same_database' => false,
        'primary_vs_archive_same_context' => false,
        'primary_vs_reading_same_database' => true,
        'primary_vs_reading_same_context' => false
      }
    end

    def context(name, role, database)
      { 'name' => name, 'role' => role, 'shard' => 'default', 'database' => database }
    end
  end

  # Reads the versioned compatibility matrix without owning execution policy.
  class Manifest
    def initialize(path)
      @data = YAML.safe_load_file(path)
    end

    def pairs
      data.fetch('pairs').map do |pair|
        Pair.new(
          ruby_version: pair.fetch('ruby'),
          rails_series: pair.fetch('rails_series')
        )
      end
    end

    def fixture_families
      data.fetch('fixture_families', ['default'])
    end

    private

    attr_reader :data
  end

  # Builds the exact-oracle view of target-specific polymorphic edges.
  class PolymorphicGroupProjector
    def self.call(render_plan)
      new(render_plan).call
    end

    def initialize(render_plan)
      @render_plan = render_plan
      @entities = render_plan.fetch('entities').to_h { |entity| [entity.fetch('safe_token'), entity] }
    end

    def call
      projections = relationships.group_by { |relationship| group_id(relationship) }.map do |id, candidates|
        projection(id, candidates)
      end
      projections.sort_by { |group| group.fetch('group_id') }
    end

    private

    attr_reader :entities, :render_plan

    def relationships
      render_plan.fetch('relationships').select do |relationship|
        relationship.fetch('relationship_id').include?('/polymorphic/')
      end
    end

    def group_id(relationship)
      relationship.fetch('relationship_id').split('/')[0...-1].join('/')
    end

    def projection(id, candidates)
      holder = candidates.first.fetch('owner_safe_token')
      {
        'group_id' => id,
        'holder_safe_token' => holder,
        'root_label' => candidates.first.fetch('label'),
        'candidate_target_safe_tokens' => candidates.map { |item| item.fetch('target_safe_token') }.uniq.sort,
        'foreign_key_attributes' => key_attributes(id, holder)
      }
    end

    def key_attributes(id, holder)
      key_names = polymorphic_key_names(id)
      entities.fetch(holder).fetch('attributes').filter_map do |attribute|
        attribute.fetch('label') if foreign_key_attribute?(attribute, key_names)
      end.uniq.sort
    end

    def polymorphic_key_names(id)
      decoded = RailsMmd::RelationshipIdCodec.decode_polymorphic_group(id)
      [*decoded.fetch(:identifier_columns), decoded.fetch(:type_column)]
    rescue RailsMmd::RelationshipIdCodec::Error => e
      raise VerificationError, "malformed polymorphic relationship ID #{id.inspect}: #{e.message}"
    end

    def foreign_key_attribute?(attribute, key_names)
      key_names.include?(attribute.fetch('label')) &&
        attribute.fetch('key_marker').split(',').map(&:strip).include?('FK')
    end
  end

  # Verifies the user-visible files emitted by a real matrix application.
  # rubocop:disable Metrics/AbcSize, Metrics/ClassLength, Metrics/MethodLength
  class ArtifactValidator
    ARTIFACT_KINDS = %w[er class].freeze
    CROSS_DOMAIN_ARTIFACTS = %w[
      core.class.mmd
      core.class.render_plan.json
      core.diagnostics.json
      core.er.mmd
      core.er.render_plan.json
      cross_domain_runtime.json
      sti_runtime.json
    ].freeze
    ENTITY_KEYS = %w[entity_id entity_kind label safe_token].freeze
    STI_ENTITY_KEYS = %w[entity_id entity_kind label safe_token].freeze
    INHERITANCE_KEYS = %w[inheritance_id parent_entity_id child_entity_id parent_safe_token child_safe_token].freeze

    def initialize(schema_validator: RailsMmd::SchemaValidator.new,
                   mermaid_serializer: RailsMmd::MermaidSerializer.new)
      @schema_validator = schema_validator
      @mermaid_serializer = mermaid_serializer
    end

    def validate(app_root, pair, fixture_family: 'default')
      output = app_root.join('tmp/rails_mmd')
      validate_cross_domain_publication_set(output, pair) if fixture_family == 'cross_domain_multi_db'
      plans = ARTIFACT_KINDS.to_h { |kind| [kind, validate_artifact(output, kind, pair)] }
      if %w[association_behavior composite_keys].include?(fixture_family)
        validate_expected_render_plans(app_root, plans, pair)
      end
      validate_expected_mermaid(app_root, output.join('core.er.mmd'), 'ER', 'rails_mmd_expected_core_er.mmd', pair)
      validate_expected_mermaid(
        app_root,
        output.join('core.class.mmd'),
        'class',
        'rails_mmd_expected_core_class.mmd',
        pair
      )
      diagnostics = output.glob('*.diagnostics.json').flat_map do |path|
        validate_json(path, pair, :diagnostics).fetch('diagnostics')
      end
      validate_expected_diagnostics(app_root, diagnostics, pair)
      validate_expected_relationships(app_root, plans.fetch('er').fetch('relationships'), pair)
      validate_expected_entities(app_root, plans.fetch('er'), pair) if fixture_family == 'cross_domain_multi_db'
      validate_expected_polymorphic_groups(app_root, plans.fetch('er'), pair)
      validate_expected_sti_entities(app_root, plans.fetch('class'), pair)
      validate_expected_inheritances(app_root, plans.fetch('class').fetch('inheritances'), pair)
      validate_expected_sti_runtime(app_root, output.join('sti_runtime.json'), pair)
      validate_fixture_runtime(app_root, output, pair, fixture_family)
    end

    private

    attr_reader :mermaid_serializer, :schema_validator

    def validate_cross_domain_publication_set(output, pair)
      actual = output.children.select(&:file?).map { |path| path.basename.to_s }.sort
      return if actual == CROSS_DOMAIN_ARTIFACTS

      raise VerificationError,
            "#{pair.name} success publication did not match expectation: #{JSON.generate(actual)}"
    end

    def validate_fixture_runtime(app_root, output, pair, fixture_family)
      return if fixture_family == 'default'

      oracle = FAMILY_RUNTIME_ORACLES.fetch(fixture_family) do
        raise VerificationError, "Missing runtime oracle wiring for fixture family: #{fixture_family}"
      end
      validate_expected_runtime(app_root, output, pair, oracle)
    end

    def validate_artifact(output, kind, pair)
      plan_path = output.join("core.#{kind}.render_plan.json")
      render_plan = validate_json(plan_path, pair, :render_plan)
      validate_mermaid(output.join("core.#{kind}.mmd"), plan_path, render_plan, pair)
      render_plan
    end

    def validate_expected_render_plans(app_root, plans, pair)
      ARTIFACT_KINDS.each do |kind|
        expected_name = "rails_mmd_expected_core_#{kind}.render_plan.json"
        expected = read_expected_json(app_root, expected_name, pair)
        next if plans.fetch(kind) == expected

        raise VerificationError, "#{pair.name} #{kind.upcase} render plan did not match expectation"
      end
    end

    def validate_mermaid(path, plan_path, render_plan, pair)
      raise VerificationError, "#{pair.name} did not publish #{path.basename}" unless path.file?

      expected = mermaid_serializer.serialize(render_plan: render_plan).text
      return if path.read == expected

      raise VerificationError, "#{pair.name} published #{path.basename} that does not match #{plan_path.basename}"
    end

    def validate_json(path, pair, schema_name)
      payload = JSON.parse(path.read)
      return payload if schema_validator.valid?(schema_name, payload)

      raise VerificationError, "#{pair.name} published schema-invalid #{path.basename}"
    rescue Errno::ENOENT, JSON::ParserError => e
      raise VerificationError, "#{pair.name} published invalid #{path.basename}: #{e.message}"
    end

    def validate_expected_mermaid(app_root, actual_path, label, expected_name, pair)
      expected_path = app_root.join(expected_name)
      expected = expected_path.read
      return if actual_path.read == expected

      raise VerificationError, "#{pair.name} #{label} Mermaid did not match expectation"
    rescue Errno::ENOENT => e
      raise VerificationError, "#{pair.name} missing expected #{expected_name}: #{e.message}"
    end

    def validate_expected_diagnostics(app_root, diagnostics, pair)
      expected = read_expected_json(app_root, 'rails_mmd_expected_diagnostics.json', pair)
      actual = diagnostics.map { |diagnostic| diagnostic_projection(diagnostic) }
      return if actual == expected

      raise VerificationError,
            "#{pair.name} diagnostics did not match expectation\n" \
            "expected: #{JSON.generate(expected)}\nactual: #{JSON.generate(actual)}"
    end

    def diagnostic_projection(diagnostic)
      %w[code severity phase scope subject_id metadata].to_h do |key|
        [key, diagnostic.fetch(key)]
      end
    end

    def validate_expected_relationships(app_root, relationships, pair)
      expected = read_expected_json(app_root, 'rails_mmd_expected_relationships.json', pair)
      actual = relationships.map { |relationship| relationship_projection(relationship) }
      return if actual == expected

      raise VerificationError,
            "#{pair.name} relationships did not match expectation\n" \
            "expected: #{JSON.generate(expected)}\nactual: #{JSON.generate(actual)}"
    end

    def validate_expected_entities(app_root, render_plan, pair)
      expected = read_expected_json(app_root, 'rails_mmd_expected_entities.json', pair)
      actual = render_plan.fetch('entities').map { |entity| projection(entity, ENTITY_KEYS) }
      return if actual == expected

      raise VerificationError,
            "#{pair.name} entities did not match expectation\n" \
            "expected: #{JSON.generate(expected)}\nactual: #{JSON.generate(actual)}"
    end

    def relationship_projection(relationship)
      keys = %w[relationship_id owner_safe_token target_safe_token label owner_cardinality target_cardinality]
      projection = keys.to_h do |key|
        [key, relationship.fetch(key)]
      end
      projection['metadata'] = relationship.fetch('metadata') if relationship.key?('metadata')
      projection
    end

    def validate_expected_polymorphic_groups(app_root, render_plan, pair)
      expected = read_expected_json(app_root, 'rails_mmd_expected_polymorphic_groups.json', pair)
      actual = PolymorphicGroupProjector.call(render_plan)
      return if actual == expected

      raise VerificationError,
            "#{pair.name} polymorphic groups did not match expectation\n" \
            "expected: #{JSON.generate(expected)}\nactual: #{JSON.generate(actual)}"
    end

    def validate_expected_sti_entities(app_root, render_plan, pair)
      expected = read_expected_json(app_root, 'rails_mmd_expected_sti_entities.json', pair)
      actual = render_plan.fetch('entities')
                          .select { |entity| entity.fetch('entity_kind') == 'sti_subtype' }
                          .map { |entity| projection(entity, STI_ENTITY_KEYS) }
      return if actual == expected

      raise VerificationError,
            "#{pair.name} STI entities did not match expectation\n" \
            "expected: #{JSON.generate(expected)}\nactual: #{JSON.generate(actual)}"
    end

    def validate_expected_inheritances(app_root, inheritances, pair)
      expected = read_expected_json(app_root, 'rails_mmd_expected_inheritances.json', pair)
      actual = inheritances.map { |inheritance| projection(inheritance, INHERITANCE_KEYS) }
      return if actual == expected

      raise VerificationError,
            "#{pair.name} inheritances did not match expectation\n" \
            "expected: #{JSON.generate(expected)}\nactual: #{JSON.generate(actual)}"
    end

    def validate_expected_sti_runtime(app_root, actual_path, pair)
      expected = read_expected_json(app_root, 'rails_mmd_expected_sti_runtime.json', pair)
      actual = JSON.parse(actual_path.read)
      return if actual == expected

      raise VerificationError,
            "#{pair.name} STI runtime did not match expectation\n" \
            "expected: #{JSON.generate(expected)}\nactual: #{JSON.generate(actual)}"
    rescue Errno::ENOENT, JSON::ParserError => e
      raise VerificationError, "#{pair.name} published invalid #{actual_path.basename}: #{e.message}"
    end

    def validate_expected_runtime(app_root, output, pair, oracle)
      actual_path = output.join(oracle.fetch(:actual))
      expected = read_expected_json(app_root, oracle.fetch(:expected), pair)
      actual = JSON.parse(actual_path.read)
      return if actual == expected

      raise VerificationError,
            "#{pair.name} #{oracle.fetch(:label)} runtime did not match expectation\n" \
            "expected: #{JSON.generate(expected)}\nactual: #{JSON.generate(actual)}"
    rescue Errno::ENOENT, JSON::ParserError => e
      raise VerificationError, "#{pair.name} published invalid #{actual_path.basename}: #{e.message}"
    end

    def projection(payload, keys)
      keys.to_h { |key| [key, payload.fetch(key)] }
    end

    def read_expected_json(app_root, expected_name, pair)
      JSON.parse(app_root.join(expected_name).read)
    rescue Errno::ENOENT, JSON::ParserError => e
      raise VerificationError, "#{pair.name} missing or invalid expected #{expected_name}: #{e.message}"
    end
  end
  # rubocop:enable Metrics/AbcSize, Metrics/ClassLength, Metrics/MethodLength

  # Verifies the fatal collision scenario remains diagnostics-only and redacted.
  class CollisionArtifactValidator
    DIAGNOSTIC_KEYS = %w[code severity phase scope subject_id metadata].freeze

    def initialize(schema_validator: RailsMmd::SchemaValidator.new)
      @schema_validator = schema_validator
    end

    def validate(app_root, pair, result)
      validate_process_result(pair, result)
      output = app_root.join('tmp/rails_mmd_collision')
      validate_publication_set(output, pair)
      document = JSON.parse(output.join('collision.diagnostics.json').read)
      validate_schema(document, pair)
      validate_redaction(document, app_root, pair)
      validate_exact_diagnostics(document, app_root, pair)
    rescue Errno::ENOENT, JSON::ParserError => e
      raise VerificationError, "#{pair.name} published invalid collision diagnostics: #{e.message}"
    end

    private

    attr_reader :schema_validator

    def validate_process_result(pair, result)
      stdout, stderr, status = result
      return if status.exitstatus == 2 && stdout.empty? && stderr.empty?

      raise VerificationError,
            "#{pair.name} collision scenario expected exit 2 with empty stdout/stderr; " \
            "got exit #{status.exitstatus}"
    end

    def validate_publication_set(output, pair)
      actual = output.children.select(&:file?).map { |path| path.basename.to_s }.sort
      expected = ['collision.diagnostics.json']
      return if actual == expected

      raise VerificationError,
            "#{pair.name} collision publication did not match expectation: #{JSON.generate(actual)}"
    end

    def validate_schema(document, pair)
      return if schema_validator.valid?(:diagnostics, document)

      raise VerificationError, "#{pair.name} published schema-invalid collision diagnostics"
    end

    def validate_redaction(document, app_root, pair)
      serialized = JSON.generate(document)
      forbidden = [app_root.to_s, '/Users/', 'password', 'passwd', 'secret', 'sqlite3://']
      leaked = forbidden.find { |value| serialized.downcase.include?(value.downcase) }
      return unless leaked

      raise VerificationError, "#{pair.name} collision diagnostics leaked forbidden connection material"
    end

    def validate_exact_diagnostics(document, app_root, pair)
      expected = JSON.parse(app_root.join('rails_mmd_expected_collision_diagnostics.json').read)
      actual = document.fetch('diagnostics').map do |diagnostic|
        DIAGNOSTIC_KEYS.to_h { |key| [key, diagnostic.fetch(key)] }
      end
      return if actual == expected

      raise VerificationError,
            "#{pair.name} collision diagnostics did not match expectation\n" \
            "expected: #{JSON.generate(expected)}\nactual: #{JSON.generate(actual)}"
    end
  end

  # Orchestrates the repository-only Rails compatibility verification command.
  # rubocop:disable Metrics/ClassLength
  class Runner
    def initialize(root: Pathname(__dir__).join('..').expand_path)
      @root = root
      @manifest = Manifest.new(root.join('fixtures/rails_matrix/matrix.yml'))
      @artifact_validator = ArtifactValidator.new
      @collision_artifact_validator = CollisionArtifactValidator.new
    end

    def run
      pairs = selected_pairs
      verify_prerequisites(pairs)
      pairs.product(selected_fixture_families).each { |pair, family| verify_pair(pair, family) }
      puts "PASS #{pairs.length}/#{pairs.length} Rails matrix pairs"
    end

    private

    attr_reader :artifact_validator, :collision_artifact_validator, :manifest, :root

    def selected_fixture_families
      selected = ENV.fetch('RAILS_MMD_MATRIX_FIXTURE_FAMILY', nil)
      return [selected] if selected

      manifest.fixture_families
    end

    def template_root
      root.join('fixtures/rails_matrix/template')
    end

    def template_family_path(family)
      return template_root if family == 'default'

      path = template_root.join('families', family)
      return path if path.directory?

      raise PrerequisiteError, "Unknown rails matrix fixture family: #{family}"
    end

    def verify_prerequisites(pairs)
      pairs.map(&:ruby_version).uniq.each do |version|
        verify_ruby(version)
        verify_bundler(version)
      end
    end

    def selected_pairs
      selector = ENV.fetch('RAILS_MMD_MATRIX_PAIR', nil)
      return manifest.pairs unless selector

      selected = manifest.pairs.select { |pair| pair.name == selector }
      raise VerificationError, "Unknown Rails matrix pair: #{selector}" if selected.empty?

      selected
    end

    def verify_ruby(version)
      return if system('asdf', 'where', 'ruby', version, out: File::NULL, err: File::NULL)

      raise PrerequisiteError, "Missing matrix Ruby #{version}; run `asdf install ruby #{version}`"
    end

    def verify_bundler(version)
      command = ['asdf', 'exec', 'bundle', "_#{Bundler::VERSION}_", '--version']
      return if unbundled_system({ 'ASDF_RUBY_VERSION' => version }, command)

      raise PrerequisiteError, bundler_install_message(version)
    end

    def bundler_install_message(version)
      "Missing Bundler #{Bundler::VERSION} for Ruby #{version}; " \
        "run `ASDF_RUBY_VERSION=#{version} asdf exec gem install bundler -v #{Bundler::VERSION}`"
    end

    def unbundled_system(env, command)
      caller_path = ENV.fetch('PATH')
      Bundler.with_unbundled_env do
        system(env.merge('PATH' => caller_path), *command, out: File::NULL, err: File::NULL)
      end
    end

    def verify_pair(pair, family)
      apps_root = root.join('.bundle/rails-matrix/apps').tap(&:mkpath)
      Dir.mktmpdir("#{pair.name}-", apps_root.to_s) do |directory|
        verify_app(Pathname(directory), pair, family)
      end
      puts "PASS #{pair.name} [#{family}]"
    end

    def verify_app(app_root, pair, family)
      prepare_app(app_root, pair, family)
      install_bundle(app_root, pair)
      run_bundle(app_root, pair, %w[exec ruby bin/rails db:schema:load])
      run_bundle(app_root, pair, %w[exec ruby bin/rails runner script/rails_mmd_sti_runtime_oracle.rb])
      run_family_runtime_oracle(app_root, pair, family)
      run_pair_probe(app_root, pair, family)
      run_bundle(app_root, pair, generate_arguments(family))
      artifact_validator.validate(app_root, pair, fixture_family: family)
      run_collision_scenario(app_root, pair) if family == 'cross_domain_multi_db'
    end

    def generate_arguments(family)
      arguments = %w[exec rails-mmd generate]
      arguments += %w[--domain core] if family == 'cross_domain_multi_db'
      arguments
    end

    def run_collision_scenario(app_root, pair)
      result = capture_bundle(
        app_root, pair, %w[exec rails-mmd generate --config rails_mmd_collision.yml]
      )
      collision_artifact_validator.validate(app_root, pair, result)
    end

    def run_family_runtime_oracle(app_root, pair, family)
      return if family == 'default'

      oracle = FAMILY_RUNTIME_ORACLES.fetch(family) do
        raise VerificationError, "Missing runtime oracle wiring for fixture family: #{family}"
      end
      run_bundle(app_root, pair, oracle.fetch(:command))
    end

    def run_pair_probe(app_root, pair, family)
      probe = PAIR_PROBES[family]
      return unless probe

      script = root.join(probe.fetch(:script))
      result = capture_bundle(app_root, pair, ['exec', 'ruby', script.to_s])
      verify_result(result, pair, "#{probe.fetch(:label)} probe")
      validate_pair_probe(JSON.parse(json_object(result.first)), pair, family)
    rescue JSON::ParserError => e
      raise VerificationError, "#{pair.name} published invalid #{probe.fetch(:label)} probe: #{e.message}"
    end

    def validate_pair_probe(payload, pair, family)
      return ConnectionBoundaryProbeValidator.new.validate(payload, pair) if family == 'cross_domain_multi_db'
      return AssociationBehaviorProbeValidator.new.validate(payload, pair) if family == 'association_behavior'

      validate_composite_habtm_probe(payload, pair)
    end

    def json_object(output)
      starts = [0] if output.start_with?('{')
      starts = [*starts, *output.enum_for(:scan, /\n\{/).map { Regexp.last_match.begin(0) + 1 }]
      starts.reverse_each do |start|
        candidate = output[start..]
        return candidate if JSON.parse(candidate).is_a?(Hash)
      rescue JSON::ParserError
        next
      end

      ''
    end

    def validate_composite_habtm_probe(payload, pair)
      expected = COMPOSITE_HABTM_EXPECTATIONS.merge(
        'rails_version' => LOCKED_RAILS_VERSIONS.fetch(pair.rails_series)
      )
      actual = expected.keys.to_h { |key| [key, payload[key]] }
      return if actual == expected

      raise VerificationError,
            "#{pair.name} composite HABTM probe did not match expectation\n" \
            "expected: #{JSON.generate(expected)}\nactual: #{JSON.generate(actual)}"
    end

    def prepare_app(app_root, pair, family)
      FileUtils.cp_r("#{template_root}/.", app_root)
      family_path = template_family_path(family)
      FileUtils.cp_r("#{family_path}/.", app_root) unless family_path == template_root
      bundle_root = root.join('fixtures/rails_matrix/bundles', pair.rails_series)
      %w[Gemfile Gemfile.lock].each do |name|
        FileUtils.cp(bundle_root.join(name), app_root.join(name))
      end
    end

    def install_bundle(app_root, pair)
      result = capture_bundle(app_root, pair, %w[check])
      result = capture_bundle(app_root, pair, %w[install]) unless result.last.success?
      verify_result(result, pair, 'bundle install')
    end

    def run_bundle(app_root, pair, arguments)
      verify_result(capture_bundle(app_root, pair, arguments), pair, arguments.join(' '))
    end

    def capture_bundle(app_root, pair, arguments)
      command = ['asdf', 'exec', 'bundle', "_#{Bundler::VERSION}_", *arguments]
      caller_path = ENV.fetch('PATH')
      Bundler.with_unbundled_env do
        Open3.capture3(pair_environment(app_root, pair, caller_path), *command, chdir: app_root.to_s)
      end
    end

    def pair_environment(app_root, pair, caller_path)
      {
        'ASDF_RUBY_VERSION' => pair.ruby_version,
        'BUNDLE_FROZEN' => 'true',
        'BUNDLE_GEMFILE' => app_root.join('Gemfile').to_s,
        'BUNDLE_PATH' => root.join('.bundle/rails-matrix/gems', pair.ruby_version).to_s,
        'PATH' => caller_path,
        'RAILS_ENV' => 'development',
        'RAILS_MMD_MATRIX_FIXTURE_FAMILY' => nil,
        'RAILS_MMD_MATRIX_PAIR' => nil
      }
    end

    def verify_result(result, pair, operation)
      stdout, stderr, status = result
      return if status.success?

      detail = [stdout, stderr].reject(&:empty?).join("\n").lines.last(20).join
      raise VerificationError, "#{pair.name} failed (exit #{status.exitstatus}): #{operation}\n#{detail}"
    end
  end
  # rubocop:enable Metrics/ClassLength
end
