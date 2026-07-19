# frozen_string_literal: true

require 'rails_mmd/generate_command'
require 'tmpdir'

# rubocop:disable Lint/ConstantDefinitionInBlock, RSpec/ExampleLength, RSpec/InstanceVariable, RSpec/LeakyConstantDeclaration, RSpec/MultipleExpectations
RSpec.describe RailsMmd::GenerateCommand do
  LoaderResult = Struct.new(:success?, :application, :diagnostics, :exit_code)

  class FakeLoader
    attr_reader :boot_count

    def initialize(result: nil, failure: nil)
      @result = result
      @failure = failure
      @boot_count = 0
    end

    def boot
      @boot_count += 1
      raise @failure if @failure

      @result
    end
  end

  class FakePipeline
    attr_reader :configs

    def initialize(result)
      @result = result
      @configs = []
    end

    def generate(config:)
      configs << config
      raise @result if @result.is_a?(Exception)

      @result
    end
  end

  it 'exposes only the Rails loader and deep pipeline as replaceable seams' do
    expect(described_class.instance_method(:initialize).parameters).to eq(
      [%i[key project_root], %i[key rails_loader], %i[key pipeline]]
    )
  end

  it 'publishes artifacts returned through the pipeline interface' do
    in_project do |root|
      result = generate(
        root,
        pipeline_result(diagnostics: [diagnostic('DB_METADATA_DEGRADED')], artifacts: valid_artifacts)
      ).run(cli_options: cli_options)

      expect(result).to be_success
      expect(root.join('out/core.er.mmd')).to exist
      expect(root.join('out/core.er.render_plan.json')).to exist
    end
  end

  it 'builds stderr when publication fails without supplying it' do
    in_project do |root|
      failure_diagnostic = diagnostic('OUTPUT_WRITE_FAILED')
      publisher = instance_double(
        RailsMmd::Publisher,
        publish: RailsMmd::Publisher::Result.new(
          success: false, diagnostics: [failure_diagnostic], written_paths: [], stderr: nil
        ),
        pre_output_stderr: "fallback stderr\n"
      )
      generator = generate(root, pipeline_result)
      allow(generator).to receive(:publisher).and_return(publisher)

      result = generator.run(cli_options: cli_options)

      expect(result.stderr).to eq("fallback stderr\n")
    end
  end

  it 'maps pipeline warnings through fail-on-warning' do
    in_project do |root|
      result = generate(root, pipeline_result(diagnostics: [diagnostic('DB_METADATA_DEGRADED')]))
               .run(cli_options: cli_options, fail_on_warning: true)

      expect(result.exit_code).to eq(1)
      expect(result.diagnostics.map { |item| item.fetch('code') }).to eq(['DB_METADATA_DEGRADED'])
    end
  end

  it 'keeps pipeline warnings successful by default' do
    in_project do |root|
      result = generate(root, pipeline_result(diagnostics: [diagnostic('DB_METADATA_DEGRADED')]))
               .run(cli_options: cli_options)

      expect(result.exit_code).to eq(0)
    end
  end

  it 'returns config failure without crossing the Rails or pipeline seams' do
    Dir.mktmpdir do |directory|
      loader = successful_loader
      pipeline = FakePipeline.new(pipeline_result)

      result = described_class.new(project_root: directory, rails_loader: loader, pipeline: pipeline)
                              .run(cli_options: cli_options)

      expect(result.exit_code).to eq(2)
      expect(loader.boot_count).to eq(0)
      expect(pipeline.configs).to be_empty
    end
  end

  it 'returns Rails boot failure without crossing the pipeline seam' do
    in_project do |root|
      loader = FakeLoader.new(result: LoaderResult.new(false, nil, [diagnostic('RAILS_LOAD_FAILED')], 2))
      pipeline = FakePipeline.new(pipeline_result)

      result = described_class.new(project_root: root, rails_loader: loader, pipeline: pipeline)
                              .run(cli_options: cli_options)

      expect(result.exit_code).to eq(2)
      expect(result.stderr).to include('RAILS_LOAD_FAILED')
      expect(pipeline.configs).to be_empty
    end
  end

  it 'maps unexpected seam failures to an internal error result' do
    in_project do |root|
      loader = FakeLoader.new(failure: RuntimeError.new("#{root}/private/boom"))

      result = described_class.new(
        project_root: root, rails_loader: loader, pipeline: FakePipeline.new(pipeline_result)
      ).run(cli_options: cli_options)

      expect(result.exit_code).to eq(99)
      expect(result.diagnostics.first.fetch('code')).to eq('INTERNAL_ERROR')
      expect(result.diagnostics.first.dig('metadata', 'exception_summary')).to eq('private/boom')
    end
  end

  it 'captures environment-backed redaction when a run starts' do
    in_project do |root|
      key = 'RAILS_MMD_LATE_SECRET'
      previous = ENV.fetch(key, nil)
      secret = 'late-secret-value'
      generator = described_class.new(
        project_root: root,
        rails_loader: FakeLoader.new(failure: RuntimeError.new(secret)),
        pipeline: FakePipeline.new(pipeline_result)
      )

      ENV[key] = secret
      result = generator.run(cli_options: cli_options)

      expect(result.diagnostics.first.dig('metadata', 'exception_summary')).to eq('[REDACTED]')
    ensure
      previous.nil? ? ENV.delete(key) : ENV[key] = previous
    end
  end

  it 'publishes pipeline errors without forging intermediate stage results' do
    in_project do |root|
      result = generate(root, pipeline_result(diagnostics: [diagnostic('MERMAID_SERIALIZATION_FAILED')]))
               .run(cli_options: cli_options)

      expect(result.exit_code).to eq(3)
      expect(root.join('out/core.diagnostics.json')).to exist
      expect(root.join('out/core.er.mmd')).not_to exist
    end
  end

  it 'maps pipeline contract errors at the command boundary' do
    in_project do |root|
      result = generate(root, pipeline_result(diagnostics: [diagnostic('DOMAIN_EMPTY')]))
               .run(cli_options: cli_options)

      expect(result.exit_code).to eq(2)
      expect(result.diagnostics.map { |item| item.fetch('code') }).to eq(['DOMAIN_EMPTY'])
      expect(root.join('out/core.diagnostics.json')).to exist
    end
  end

  def generate(root, result)
    described_class.new(project_root: root, rails_loader: successful_loader, pipeline: FakePipeline.new(result))
  end

  def successful_loader
    FakeLoader.new(result: LoaderResult.new(true, Object.new, [], 0))
  end

  def pipeline_result(diagnostics: [], artifacts: {})
    RailsMmd::GenerationPipeline::Result.new(diagnostics: diagnostics, artifacts: artifacts)
  end

  def valid_artifacts
    {
      'core' => {
        'er' => {
          render_plan: JSON.parse(File.read('fixtures/schemas/render_plan/valid/er.json')),
          mermaid: "erDiagram\n"
        }
      }
    }
  end

  def diagnostic(code)
    diagnostics_catalog.find { |item| item.fetch('code') == code }.dup
  end

  def diagnostics_catalog
    @diagnostics_catalog ||= JSON.parse(
      File.read('fixtures/schemas/diagnostics/valid/catalog.json')
    ).fetch('diagnostics')
  end

  def cli_options
    RailsMmd::Config::CliOptions.new
  end

  def in_project
    Dir.mktmpdir do |directory|
      root = Pathname(directory)
      root.join('rails_mmd.yml').write(config_yaml)
      yield root
    end
  end

  def config_yaml
    <<~YAML
      version: 1
      domains:
        core:
          include_models: [User]
          exclude_models: []
      output:
        directory: out
        format: er
        attributes: keys
        direction: LR
    YAML
  end
end
# rubocop:enable Lint/ConstantDefinitionInBlock, RSpec/ExampleLength, RSpec/InstanceVariable, RSpec/LeakyConstantDeclaration, RSpec/MultipleExpectations
