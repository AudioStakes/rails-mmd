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
    }
  }.freeze

  PAIR_PROBES = {
    'composite_keys' => {
      script: 'docs/p2/04-composite-keys/probes/composite_habtm_probe.rb',
      label: 'composite HABTM'
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
    STI_ENTITY_KEYS = %w[entity_id entity_kind label safe_token].freeze
    INHERITANCE_KEYS = %w[inheritance_id parent_entity_id child_entity_id parent_safe_token child_safe_token].freeze

    def initialize(schema_validator: RailsMmd::SchemaValidator.new,
                   mermaid_serializer: RailsMmd::MermaidSerializer.new)
      @schema_validator = schema_validator
      @mermaid_serializer = mermaid_serializer
    end

    def validate(app_root, pair, fixture_family: 'default')
      output = app_root.join('tmp/rails_mmd')
      plans = ARTIFACT_KINDS.to_h { |kind| [kind, validate_artifact(output, kind, pair)] }
      validate_expected_render_plans(app_root, plans, pair) if fixture_family == 'composite_keys'
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
      validate_expected_polymorphic_groups(app_root, plans.fetch('er'), pair)
      validate_expected_sti_entities(app_root, plans.fetch('class'), pair)
      validate_expected_inheritances(app_root, plans.fetch('class').fetch('inheritances'), pair)
      validate_expected_sti_runtime(app_root, output.join('sti_runtime.json'), pair)
      validate_fixture_runtime(app_root, output, pair, fixture_family)
    end

    private

    attr_reader :mermaid_serializer, :schema_validator

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

  # Orchestrates the repository-only Rails compatibility verification command.
  # rubocop:disable Metrics/ClassLength
  class Runner
    def initialize(root: Pathname(__dir__).join('..').expand_path)
      @root = root
      @manifest = Manifest.new(root.join('fixtures/rails_matrix/matrix.yml'))
      @artifact_validator = ArtifactValidator.new
    end

    def run
      pairs = selected_pairs
      verify_prerequisites(pairs)
      pairs.product(selected_fixture_families).each { |pair, family| verify_pair(pair, family) }
      puts "PASS #{pairs.length}/#{pairs.length} Rails matrix pairs"
    end

    private

    attr_reader :artifact_validator, :manifest, :root

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
      run_bundle(app_root, pair, %w[exec rails-mmd generate])
      artifact_validator.validate(app_root, pair, fixture_family: family)
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
      validate_composite_habtm_probe(JSON.parse(json_object(result.first)), pair)
    rescue JSON::ParserError => e
      raise VerificationError, "#{pair.name} published invalid #{probe.fetch(:label)} probe: #{e.message}"
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
