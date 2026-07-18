# frozen_string_literal: true

require 'rails_mmd/generate'

# rubocop:disable RSpec/MultipleExpectations
RSpec.describe RailsMmd::Generate do
  subject(:generate) { described_class.new(project_root: Dir.pwd, dependencies: dependencies) }

  let(:dependencies) do
    {
      config_loader: config_loader,
      rails_loader: rails_loader,
      model_inventory: model_inventory,
      domain_resolver: domain_resolver,
      schema_probe: schema_probe,
      relationship_builder: relationship_builder,
      ir_builder: ir_builder,
      render_plan_builder: render_plan_builder,
      mermaid_serializer: mermaid_serializer,
      publisher: publisher
    }
  end

  it 'routes successful pipeline artifacts to the publisher and returns its exit policy' do
    result = generate.run(cli_options: RailsMmd::Config::CliOptions.new, fail_on_warning: true)

    expect(result.exit_code).to eq(1), result.diagnostics.inspect
    expect(result.stderr).to be_empty
    expect(publisher.received.fetch(:selected_domain_ids)).to eq(['core'])
    expect(publisher.received.fetch(:artifacts).fetch('core').keys).to eq(%w[er class])
  end

  it 'keeps warning diagnostics successful when fail-on-warning is disabled' do
    result = generate.run(cli_options: RailsMmd::Config::CliOptions.new)

    expect(result.exit_code).to eq(0), result.diagnostics.inspect
    expect(result.stderr).to be_empty
    expect(publisher.received.fetch(:diagnostics)).to include(warning_diagnostic)
  end

  it 'includes render-plan diagnostics in published diagnostics and exit policy' do
    render_plan_builder.diagnostics = [safe_token_collision]

    result = generate.run(cli_options: RailsMmd::Config::CliOptions.new)

    expect(result.exit_code).to eq(3)
    expect(publisher.received.fetch(:diagnostics)).to include(safe_token_collision)
  end

  it 'maps Mermaid serialization fatal diagnostics through the pipeline exit policy' do
    mermaid_serializer.diagnostics = [mermaid_serialization_failed]

    result = generate.run(cli_options: RailsMmd::Config::CliOptions.new)

    expect(result.exit_code).to eq(3)
    expect(publisher.received.fetch(:diagnostics)).to include(mermaid_serialization_failed)
    expect(publisher.received.fetch(:artifacts).fetch('core')).to be_empty
  end

  it 'publishes serialization diagnostics without converting them to output write failures' do
    Dir.mktmpdir do |root|
      result = run_generate_with_real_publisher_serialization_failure(root)

      expect_serialization_failure_published_without_artifacts(result, Pathname(root).join('out'))
    end
  end

  it 'returns pre-output diagnostics without running later pipeline stages when config fails' do
    config_loader.result = failure_result([warning_diagnostic.merge('code' => 'CONFIG_NOT_FOUND')], 2)

    result = generate.run(cli_options: RailsMmd::Config::CliOptions.new)

    expect(result.exit_code).to eq(2)
    expect(result.stderr).to include('CONFIG_NOT_FOUND')
    expect(publisher.received).to be_nil
  end

  it 'returns pre-output diagnostics without publishing when Rails boot fails' do
    rails_loader.result = failure_result([warning_diagnostic.merge('code' => 'RAILS_LOAD_FAILED')], 2)

    result = generate.run(cli_options: RailsMmd::Config::CliOptions.new)

    expect(result.exit_code).to eq(2)
    expect(result.stderr).to include('RAILS_LOAD_FAILED')
    expect(publisher.received).to be_nil
  end

  it 'maps unexpected exceptions to internal error results' do
    config_loader.result = success_result(config)
    allow(rails_loader).to receive(:boot).and_raise(RuntimeError, 'boom')

    result = generate.run(cli_options: RailsMmd::Config::CliOptions.new)

    expect(result.exit_code).to eq(99)
    expect(result.diagnostics.first.fetch('code')).to eq('INTERNAL_ERROR')
  end

  it 'builds model inventory from an injected ActiveRecord base when no inventory is injected' do
    use_active_record_base_inventory

    result = generate.run(cli_options: RailsMmd::Config::CliOptions.new)

    expect(result.exit_code).to eq(0)
    expect(result).to be_success
  end

  it 'maps blocking diagnostics through exit policy' do
    expect(RailsMmd::ExitPolicy.exit_code([output_write_failed])).to eq(4)
    expect(RailsMmd::ExitPolicy.exit_code([output_write_failed, warning_diagnostic], fail_on_warning: true)).to eq(4)
    expect(RailsMmd::ExitPolicy.exit_code([])).to eq(0)
  end

  it 'writes publish failure diagnostics to stderr' do
    publisher.failure_diagnostics = [output_write_failed]

    result = generate.run(cli_options: RailsMmd::Config::CliOptions.new)

    expect(result.exit_code).to eq(4)
    expect(result.stderr).to include('OUTPUT_WRITE_FAILED')
  end

  it 'preserves explicit publisher stderr on publish failure' do
    publisher.failure_diagnostics = [output_write_failed]
    publisher.failure_stderr = 'publish failed'

    result = generate.run(cli_options: RailsMmd::Config::CliOptions.new)

    expect(result.exit_code).to eq(4)
    expect(result.stderr).to eq('publish failed')
  end

  it 'resolves constants with the default model resolver' do
    expect(generate.send(:model_resolver).call('String')).to eq(String)
  end

  def config_loader
    @config_loader ||= fake_loader(success_result(config))
  end

  def rails_loader
    @rails_loader ||= fake_loader(success_result(Object.new, application: Object.new))
  end

  def model_inventory
    @model_inventory ||= Struct.new(:records).new([])
  end

  def domain_resolver
    @domain_resolver ||= fake_stage(domains: [domain_result], diagnostics: [warning_diagnostic])
  end

  def schema_probe
    @schema_probe ||= fake_stage(domains: [domain_result], diagnostics: [])
  end

  def relationship_builder
    @relationship_builder ||= fake_stage(domains: [domain_result], diagnostics: [])
  end

  def ir_builder
    @ir_builder ||= Struct.new(:domains) do
      def build(**)
        self
      end
    end.new([Struct.new(:domain_id, :payload).new('core', { 'domain_id' => 'core', 'diagnostic_ids' => [] })])
  end

  def render_plan_builder
    @render_plan_builder ||= Struct.new(:payload, :diagnostics) do
      def build(artifact_kind:, **kwargs)
        input_ir = kwargs.fetch(:ir)
        self.payload = { 'domain_id' => input_ir.fetch('domain_id'), 'artifact_kind' => artifact_kind,
                         'diagnostic_ids' => [] }
        self
      end
    end.new(nil, [])
  end

  def mermaid_serializer
    @mermaid_serializer ||= Struct.new(:text, :diagnostics) do
      def serialize(render_plan:)
        self.text = "#{render_plan.fetch('artifact_kind')}Diagram\n"
        Struct.new(:text, :diagnostics).new(text, diagnostics)
      end
    end.new(nil, [])
  end

  def publisher
    diagnostic = warning_diagnostic
    received = {}
    @publisher ||= Object.new.tap do |fake|
      define_fake_publisher_methods(fake, received, diagnostic)
    end
  end

  def define_fake_publisher_methods(fake, received, diagnostic)
    failure_diagnostics = {}
    failure_stderr = {}
    fake.define_singleton_method(:received) { received[:value] }
    fake.define_singleton_method(:failure_diagnostics=) { |diagnostics| failure_diagnostics[:value] = diagnostics }
    fake.define_singleton_method(:failure_stderr=) { |stderr| failure_stderr[:value] = stderr }
    define_fake_publish(fake, received, diagnostic, failure_diagnostics, failure_stderr)
    fake.define_singleton_method(:pre_output_stderr) do |diagnostics|
      diagnostics.map { |item| item.fetch('code') }.join("\n")
    end
  end

  def define_fake_publish(fake, received, diagnostic, failure_diagnostics, failure_stderr)
    result_factory = method(:publisher_result_for)
    fake.define_singleton_method(:publish) do |**kwargs|
      received[:value] = kwargs
      result_factory.call(kwargs, diagnostic, failure_diagnostics, failure_stderr)
    end
  end

  def publisher_result_for(kwargs, diagnostic, failure_diagnostics, failure_stderr)
    if failure_diagnostics[:value]
      Struct.new(:success?, :diagnostics, :stderr).new(
        false,
        failure_diagnostics.fetch(:value),
        failure_stderr.fetch(:value, '')
      )
    else
      Struct.new(:success?, :diagnostics, :stderr).new(true, kwargs.fetch(:diagnostics) + [diagnostic], '')
    end
  end

  def config
    output = RailsMmd::Config::Output.new(directory: 'out', format: 'both', attributes: 'keys', direction: 'LR')
    RailsMmd::Config::Resolved.new(domains: { 'core' => Object.new }, output: output, selected_domain_ids: ['core'])
  end

  def domain_result
    Struct.new(:domain_id, :diagnostics, :records, :entities, :relationships).new('core', [], [], [], [])
  end

  def fake_loader(result)
    Struct.new(:result) do
      def load(**) = result

      def boot = result
    end.new(result)
  end

  def fake_stage(domains:, diagnostics:)
    Struct.new(:domains, :diagnostics) do
      def resolve(**) = self

      def probe(**) = self

      def build(**) = self
    end.new(domains, diagnostics)
  end

  def success_result(config_value, application: nil)
    Struct.new(:success?, :config, :application, :diagnostics, :exit_code).new(true, config_value, application, [], 0)
  end

  def failure_result(diagnostics, exit_code)
    Struct.new(:success?, :diagnostics, :exit_code).new(false, diagnostics, exit_code)
  end

  def warning_diagnostic
    {
      'diagnostic_id' => 'warning',
      'code' => 'DB_METADATA_DEGRADED',
      'severity' => 'warning',
      'subject_id' => 'core'
    }
  end

  def output_write_failed
    {
      'diagnostic_id' => 'write',
      'code' => 'OUTPUT_WRITE_FAILED',
      'severity' => 'error',
      'subject_id' => nil
    }
  end

  def safe_token_collision
    {
      'diagnostic_id' => 'collision',
      'code' => 'SAFE_TOKEN_COLLISION',
      'severity' => 'fatal',
      'subject_id' => 'core:er'
    }
  end

  def mermaid_serialization_failed
    {
      'diagnostic_id' => 'serialization',
      'code' => 'MERMAID_SERIALIZATION_FAILED',
      'severity' => 'fatal',
      'subject_id' => 'core:er'
    }
  end

  def use_active_record_base_inventory
    dependencies.delete(:model_inventory)
    dependencies[:active_record_base] = Class.new do
      def self.descendants = []
    end
  end

  def real_publisher_serialization_failure_dependencies(root)
    real_publisher_pipeline_dependencies.merge(
      render_plan_builder: invalid_render_plan_builder,
      publisher: RailsMmd::Publisher.new(project_root: root)
    )
  end

  def real_publisher_pipeline_dependencies
    {
      config_loader: fake_loader(success_result(real_publisher_config)),
      rails_loader: fake_loader(success_result(Object.new, application: Object.new)),
      model_inventory: model_inventory,
      domain_resolver: fake_stage(domains: [domain_result], diagnostics: []),
      schema_probe: fake_stage(domains: [domain_result], diagnostics: []),
      relationship_builder: fake_stage(domains: [domain_result], diagnostics: []),
      ir_builder: ir_builder
    }
  end

  def real_publisher_config
    output = RailsMmd::Config::Output.new(directory: 'out', format: 'er', attributes: 'keys', direction: 'LR')
    RailsMmd::Config::Resolved.new(domains: { 'core' => Object.new }, output: output, selected_domain_ids: ['core'])
  end

  def invalid_render_plan_builder
    Struct.new(:payload, :diagnostics) do
      def build(artifact_kind:, **kwargs)
        input_ir = kwargs.fetch(:ir)
        self.payload = invalid_payload(input_ir, artifact_kind)
        self
      end

      def invalid_payload(input_ir, artifact_kind)
        { 'domain_id' => input_ir.fetch('domain_id'), 'artifact_kind' => artifact_kind, 'diagnostic_ids' => [] }
      end
    end.new(nil, [])
  end

  def run_generate_with_real_publisher_serialization_failure(root)
    described_class.new(
      project_root: root,
      dependencies: real_publisher_serialization_failure_dependencies(root)
    ).run(cli_options: RailsMmd::Config::CliOptions.new)
  end

  def expect_serialization_failure_published_without_artifacts(result, output)
    aggregate_failures do
      expect_serialization_failure_result(result)
      expect_serialization_failure_artifacts(output)
    end
  end

  def expect_serialization_failure_result(result)
    expect(result.exit_code).to eq(3)
    expect(result.diagnostics.map { |diagnostic| diagnostic.fetch('code') })
      .to contain_exactly('MERMAID_SERIALIZATION_FAILED')
    expect(result.diagnostics.map { |diagnostic| diagnostic.fetch('code') }).not_to include('OUTPUT_WRITE_FAILED')
  end

  def expect_serialization_failure_artifacts(output)
    expect(output.join('core.diagnostics.json')).to exist
    expect(output.join('core.er.mmd')).not_to exist
    expect(output.join('core.er.render_plan.json')).not_to exist
  end
end
# rubocop:enable RSpec/MultipleExpectations
