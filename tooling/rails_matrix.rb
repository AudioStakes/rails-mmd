# frozen_string_literal: true

require 'bundler'
require 'fileutils'
require 'json'
require 'open3'
require 'pathname'
require 'tmpdir'
require 'yaml'
require 'rails_mmd/mermaid_serializer'
require 'rails_mmd/schema_validator'

module RailsMatrix
  class PrerequisiteError < StandardError; end
  class VerificationError < StandardError; end

  Pair = Data.define(:ruby_version, :rails_series) do
    def name
      "ruby-#{ruby_version}-rails-#{rails_series}"
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
      key_names = id.split('/').last(2)
      entities.fetch(holder).fetch('attributes').filter_map do |attribute|
        label = attribute.fetch('label')
        label if key_names.include?(label) && attribute.fetch('key_marker') == 'FK'
      end.uniq.sort
    end
  end

  # Verifies the user-visible files emitted by a real matrix application.
  class ArtifactValidator
    ARTIFACT_KINDS = %w[er class].freeze

    def initialize(schema_validator: RailsMmd::SchemaValidator.new,
                   mermaid_serializer: RailsMmd::MermaidSerializer.new)
      @schema_validator = schema_validator
      @mermaid_serializer = mermaid_serializer
    end

    def validate(app_root, pair)
      output = app_root.join('tmp/rails_mmd')
      plans = ARTIFACT_KINDS.to_h { |kind| [kind, validate_artifact(output, kind, pair)] }
      diagnostics = output.glob('*.diagnostics.json').flat_map do |path|
        validate_json(path, pair, :diagnostics).fetch('diagnostics')
      end
      validate_expected_diagnostics(app_root, diagnostics, pair)
      validate_expected_relationships(app_root, plans.fetch('er').fetch('relationships'), pair)
      validate_expected_polymorphic_groups(app_root, plans.fetch('er'), pair)
    end

    private

    attr_reader :mermaid_serializer, :schema_validator

    def validate_artifact(output, kind, pair)
      plan_path = output.join("core.#{kind}.render_plan.json")
      render_plan = validate_json(plan_path, pair, :render_plan)
      validate_mermaid(output.join("core.#{kind}.mmd"), plan_path, render_plan, pair)
      render_plan
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

    def validate_expected_diagnostics(app_root, diagnostics, pair)
      expected = JSON.parse(app_root.join('rails_mmd_expected_diagnostics.json').read)
      expected_codes = expected.map { |diagnostic| diagnostic.fetch('code') }.uniq
      actual = diagnostics
               .select { |diagnostic| expected_codes.include?(diagnostic.fetch('code')) }
               .map { |diagnostic| diagnostic_projection(diagnostic) }
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
      expected = JSON.parse(app_root.join('rails_mmd_expected_relationships.json').read)
      actual = relationships.map { |relationship| relationship_projection(relationship) }
      return if actual == expected

      raise VerificationError,
            "#{pair.name} relationships did not match expectation\n" \
            "expected: #{JSON.generate(expected)}\nactual: #{JSON.generate(actual)}"
    end

    def relationship_projection(relationship)
      %w[relationship_id owner_safe_token target_safe_token label owner_cardinality target_cardinality].to_h do |key|
        [key, relationship.fetch(key)]
      end
    end

    def validate_expected_polymorphic_groups(app_root, render_plan, pair)
      expected = JSON.parse(app_root.join('rails_mmd_expected_polymorphic_groups.json').read)
      actual = PolymorphicGroupProjector.call(render_plan)
      return if actual == expected

      raise VerificationError,
            "#{pair.name} polymorphic groups did not match expectation\n" \
            "expected: #{JSON.generate(expected)}\nactual: #{JSON.generate(actual)}"
    end
  end

  # Orchestrates the repository-only Rails compatibility verification command.
  class Runner
    def initialize(root: Pathname(__dir__).join('..').expand_path)
      @root = root
      @manifest = Manifest.new(root.join('fixtures/rails_matrix/matrix.yml'))
      @artifact_validator = ArtifactValidator.new
    end

    def run
      pairs = selected_pairs
      verify_prerequisites(pairs)
      pairs.each { |pair| verify_pair(pair) }
      puts "PASS #{pairs.length}/#{pairs.length} Rails matrix pairs"
    end

    private

    attr_reader :artifact_validator, :manifest, :root

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

    def verify_pair(pair)
      apps_root = root.join('.bundle/rails-matrix/apps').tap(&:mkpath)
      Dir.mktmpdir("#{pair.name}-", apps_root.to_s) do |directory|
        app_root = Pathname(directory)
        prepare_app(app_root, pair)
        install_bundle(app_root, pair)
        run_bundle(app_root, pair, %w[exec ruby bin/rails db:schema:load])
        run_bundle(app_root, pair, %w[exec rails-mmd generate])
        artifact_validator.validate(app_root, pair)
      end
      puts "PASS #{pair.name}"
    end

    def prepare_app(app_root, pair)
      FileUtils.cp_r("#{root.join('fixtures/rails_matrix/template')}/.", app_root)
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
        'RAILS_ENV' => 'development'
      }
    end

    def verify_result(result, pair, operation)
      stdout, stderr, status = result
      return if status.success?

      detail = [stdout, stderr].reject(&:empty?).join("\n").lines.last(20).join
      raise VerificationError, "#{pair.name} failed (exit #{status.exitstatus}): #{operation}\n#{detail}"
    end
  end
end
