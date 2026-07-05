# frozen_string_literal: true

require 'json'
require 'tmpdir'
require 'rails_mmd/canonical_json'
require 'rails_mmd/config'
require 'rails_mmd/schema_validator'

# rubocop:disable RSpec/ExampleLength, RSpec/InstanceVariable, RSpec/MultipleExpectations
RSpec.describe RailsMmd::Config do
  around do |example|
    Dir.mktmpdir do |root|
      @project_root = Pathname(root)
      example.run
    end
  end

  def write_config(content)
    project_root.join('rails_mmd.yml').write(content)
  end

  def load_config(**)
    described_class.new(project_root: project_root).load(
      cli_options: described_class::CliOptions.new(**)
    )
  end

  def expect_schema_valid_diagnostic(diagnostic)
    envelope = {
      'schema_version' => 1,
      'scope' => 'global',
      'domain_id' => nil,
      'diagnostics' => [diagnostic],
      'digest_sha256' => RailsMmd::CanonicalJson.digest_sha256(diagnostic)
    }

    expect(RailsMmd::SchemaValidator.new.valid?(:diagnostics, envelope)).to be(true)
  end

  let(:project_root) { @project_root }

  it 'loads the default rails_mmd.yml and applies documented defaults' do
    write_config(<<~YAML)
      version: 1
      domains:
        core:
          include_models:
            - User
    YAML

    result = load_config

    expect(result).to be_success
    expect(result.exit_code).to eq(0)
    expect(result.config.output.directory).to eq('docs/rails_mmd')
    expect(result.config.output.format).to eq('both')
    expect(result.config.output.attributes).to eq('keys')
    expect(result.config.output.direction).to eq('LR')
    expect(result.config.domains.fetch('core').exclude_models).to eq([])
    expect(result.config.selected_domain_ids).to eq(['core'])
  end

  it 'lets explicit CLI values override config values while config overrides defaults' do
    write_config(<<~YAML)
      version: 1
      domains:
        core:
          include_models:
            - User
      output:
        directory: docs/from_config
        format: er
        attributes: none
        direction: TB
    YAML

    result = load_config(output_dir: 'docs/from_cli', format: 'class')

    expect(result).to be_success
    expect(result.config.output.directory).to eq('docs/from_cli')
    expect(result.config.output.format).to eq('class')
    expect(result.config.output.attributes).to eq('none')
    expect(result.config.output.direction).to eq('TB')
    expect(result.config.output.sources).to include(
      'directory' => 'cli',
      'format' => 'cli',
      'attributes' => 'config',
      'direction' => 'config'
    )
  end

  it 'reads an explicit future CLI config path' do
    project_root.join('config').mkpath
    project_root.join('config/diagrams.yml').write(<<~YAML)
      version: 1
      domains:
        admin:
          include_models:
            - Admin::User
    YAML

    result = load_config(config_path: 'config/diagrams.yml')

    expect(result).to be_success
    expect(result.config.config_path).to eq(project_root.join('config/diagrams.yml'))
  end

  it 'returns a schema-valid CONFIG_NOT_FOUND diagnostic without writes' do
    result = load_config

    expect(result).not_to be_success
    expect(result.exit_code).to eq(2)
    expect(result.diagnostics.first).to include('code' => 'CONFIG_NOT_FOUND')
    expect_schema_valid_diagnostic(result.diagnostics.first)
    expect(project_root.children).to be_empty
  end

  it 'redacts missing config paths outside the project root' do
    result = load_config(config_path: project_root.parent.join('missing.yml').to_s)

    expect(result).not_to be_success
    expect(result.diagnostics.first).to include('code' => 'CONFIG_NOT_FOUND')
    expect(result.diagnostics.first.fetch('metadata')).to include('config_path' => 'rails_mmd.yml')
    expect_schema_valid_diagnostic(result.diagnostics.first)
  end

  it 'uses safe YAML loading and rejects aliases' do
    write_config(<<~YAML)
      version: 1
      domains:
        core: &core
          include_models:
            - User
        billing: *core
    YAML

    result = load_config

    expect(result).not_to be_success
    expect(result.diagnostics.first).to include('code' => 'CONFIG_SCHEMA_INVALID')
    expect_schema_valid_diagnostic(result.diagnostics.first)
  end

  it 'does not expand ERB while parsing YAML' do
    write_config(<<~YAML)
      version: 1
      domains:
        core:
          include_models:
            - User
      output:
        directory: "<%= FileUtils.mkdir_p('created_by_erb') %>"
    YAML

    result = load_config

    expect(result).not_to be_success
    expect(result.diagnostics.first).to include('code' => 'OUTPUT_DIRECTORY_INVALID')
    expect(project_root.join('created_by_erb')).not_to exist
  end

  it 'rejects unknown config fields through the JSON schema' do
    write_config(<<~YAML)
      version: 1
      domains:
        core:
          include_models:
            - User
          depth: 2
    YAML

    result = load_config

    expect(result).not_to be_success
    expect(result.diagnostics.first).to include('code' => 'CONFIG_SCHEMA_INVALID')
    expect(result.diagnostics.first.fetch('metadata')).to include('field_path' => '$.domains.core.depth')
    expect_schema_valid_diagnostic(result.diagnostics.first)
  end

  it 'represents unknown domain selection as CONFIG_DOMAIN_NOT_FOUND' do
    write_config(<<~YAML)
      version: 1
      domains:
        core:
          include_models:
            - User
    YAML

    result = load_config(domain: 'billing_v2')

    expect(result).not_to be_success
    expect(result.diagnostics.first).to include('code' => 'CONFIG_DOMAIN_NOT_FOUND')
    expect_schema_valid_diagnostic(result.diagnostics.first)
  end

  it 'rejects malformed CLI domain selections without raising' do
    write_config(<<~YAML)
      version: 1
      domains:
        core:
          include_models:
            - User
    YAML

    ['billing-v2', 'billing v2', 'Billing', '../evil', "core\n"].each do |domain|
      result = load_config(domain: domain)

      expect(result).not_to be_success
      expect(result.exit_code).to eq(2)
      expect(result.diagnostics.first).to include('code' => 'CONFIG_SCHEMA_INVALID')
      expect(result.diagnostics.first.fetch('metadata')).to include('field_path' => '$.cli.domain')
      expect_schema_valid_diagnostic(result.diagnostics.first)
    end
  end

  it 'reports invalid CLI format with the canonical field path' do
    write_config(<<~YAML)
      version: 1
      domains:
        core:
          include_models:
            - User
    YAML

    result = load_config(format: 'svg')

    expect(result).not_to be_success
    expect(result.diagnostics.first).to include('code' => 'CONFIG_SCHEMA_INVALID')
    expect(result.diagnostics.first.fetch('metadata')).to include('field_path' => '$.cli.format')
    expect_schema_valid_diagnostic(result.diagnostics.first)
  end

  it 'validates effective CLI output overrides instead of stale config values' do
    write_config(<<~YAML)
      version: 1
      domains:
        core:
          include_models:
            - User
      output:
        directory: /tmp/oops
        format: invalid
    YAML

    result = load_config(output_dir: 'docs/safe', format: 'er')

    expect(result).to be_success
    expect(result.config.output.directory).to eq('docs/safe')
    expect(result.config.output.format).to eq('er')
  end

  it 'validates domain IDs with the repository grammar through the config schema' do
    examples = JSON.parse(Pathname('fixtures/schemas/config/domain_id_examples.json').read)

    accepted = examples.fetch('positive').select { |domain_id| valid_domain_id?(domain_id) }
    rejected = examples.fetch('negative').select { |domain_id| valid_domain_id?(domain_id) }

    expect(accepted).to eq(examples.fetch('positive'))
    expect(rejected).to be_empty
  end

  it 'rejects unsafe output directories with schema-valid OUTPUT_DIRECTORY_INVALID diagnostics' do
    rejected_paths = [
      '',
      '.',
      '..',
      '../outside',
      '/tmp/rails_mmd',
      'docs\\rails_mmd',
      "docs\u0000rails_mmd",
      'C:\\rails_mmd',
      '\\\\server\\share'
    ]

    rejected_paths.each do |path|
      write_config(<<~YAML)
        version: 1
        domains:
          core:
            include_models:
              - User
        output:
          directory: #{path.inspect}
      YAML

      result = load_config

      expect(result).not_to be_success
      expect(result.diagnostics.first).to include('code' => 'OUTPUT_DIRECTORY_INVALID')
      expect(result.diagnostics.first.fetch('metadata')).to include('field_path' => '$.output.directory')
      expect_schema_valid_diagnostic(result.diagnostics.first)
    end
  end

  it 'reports invalid CLI output directory with the canonical field path' do
    write_config(<<~YAML)
      version: 1
      domains:
        core:
          include_models:
            - User
    YAML

    result = load_config(output_dir: '/tmp/oops')

    expect(result).not_to be_success
    expect(result.diagnostics.first).to include('code' => 'OUTPUT_DIRECTORY_INVALID')
    expect(result.diagnostics.first.fetch('metadata')).to include('field_path' => '$.cli.output_dir')
    expect_schema_valid_diagnostic(result.diagnostics.first)
  end

  it 'rejects output directories that escape through symlinks' do
    Dir.mktmpdir do |outside|
      project_root.join('links').mkpath
      File.symlink(outside, project_root.join('links/outside'))
      write_config(<<~YAML)
        version: 1
        domains:
          core:
            include_models:
              - User
        output:
          directory: links/outside/artifacts
      YAML

      result = load_config

      expect(result).not_to be_success
      expect(result.diagnostics.first).to include('code' => 'OUTPUT_DIRECTORY_INVALID')
      expect_schema_valid_diagnostic(result.diagnostics.first)
    end
  end

  it 'treats disappearing output path ancestors as invalid' do
    resolver = RailsMmd::OutputDirectory.new(project_root: project_root)
    allow(resolver).to receive(:closest_existing_path).and_return(project_root.join('gone'))

    result = resolver.resolve('docs/rails_mmd')

    expect(result).not_to be_valid
    expect(result.reason).to eq('symlink escapes project root')
  end

  def valid_domain_id?(domain_id)
    project_root.join('rails_mmd.yml').write({
      'version' => 1,
      'domains' => {
        domain_id => { 'include_models' => ['User'] }
      }
    }.to_yaml)

    load_config.success?
  end
end
# rubocop:enable RSpec/ExampleLength, RSpec/InstanceVariable, RSpec/MultipleExpectations
