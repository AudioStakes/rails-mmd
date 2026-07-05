# frozen_string_literal: true

require 'open3'
require 'json'
require 'rails_mmd/cli'
require 'rails_mmd/version'

RSpec.describe RailsMmd::CLI do
  def run_cli(*)
    Open3.capture3('bundle', 'exec', 'exe/rails-mmd', *)
  end

  describe '--help' do
    subject(:result) { run_cli('--help') }

    it 'succeeds' do
      expect(result[2]).to be_success
    end

    it 'writes no error output' do
      expect(result[1]).to be_empty
    end

    it 'prints help, generate, and version commands' do
      expect(result[0]).to include('rails-mmd generate', 'rails-mmd help [COMMAND]', 'rails-mmd version')
    end

    it 'does not expose excluded P0 option names' do
      expect(result[0]).not_to match(/\.erdconfig|--strict|--no-strict|--allow-partial|--validate|--cache/)
    end
  end

  describe '--version' do
    subject(:result) { run_cli('--version') }

    it 'succeeds' do
      expect(result[2]).to be_success
    end

    it 'writes no error output' do
      expect(result[1]).to be_empty
    end

    it 'prints the version' do
      expect(result[0]).to eq("#{RailsMmd::VERSION}\n")
    end
  end

  it 'uses Thor failure exits for command errors' do
    expect(described_class.exit_on_failure?).to be(true)
  end

  it 'prints the version from the Thor command implementation' do
    expect { described_class.new.version }.to output("#{RailsMmd::VERSION}\n").to_stdout
  end

  it 'loads the gem version constant' do
    expect(RailsMmd::VERSION).to eq('0.1.0')
  end

  it 'runs generate through Thor in process' do
    generator = stub_generator

    expect { described_class.start(%w[generate --config config.yml]) }.to raise_error(SystemExit)
    expect_generator_config(generator)
  end

  it 'passes a true fail-on-warning flag through Thor in process' do
    generator = stub_generator

    expect do
      described_class.start(%w[generate --config config.yml --fail-on-warning=true])
    end.to raise_error(SystemExit)
    expect_generator_fail_on_warning(generator, true)
  end

  it 'passes a bare fail-on-warning flag through Thor in process' do
    generator = stub_generator

    expect do
      described_class.start(%w[generate --config config.yml --fail-on-warning])
    end.to raise_error(SystemExit)
    expect_generator_fail_on_warning(generator, true)
  end

  it 'ignores non-true fail-on-warning values through Thor in process' do
    generator = stub_generator

    expect do
      described_class.start(%w[generate --config config.yml --fail-on-warning=false])
    end.to raise_error(SystemExit)
    expect_generator_fail_on_warning(generator, false)
  end

  it 'prints generate command help through Thor in process' do
    expect { described_class.start(%w[generate --help]) }.to output(/--output-dir/).to_stdout
  end

  describe 'generate' do
    it 'prints P0 options in command help' do
      stdout, stderr, status = run_cli('generate', '--help')

      expect_generate_help(stdout, stderr, status)
    end

    it 'returns sanitized CONFIG_NOT_FOUND diagnostics when no config exists' do
      stdout, stderr, status = run_cli('generate')

      expect_config_not_found(stdout, stderr, status)
    end
  end

  def expect_generate_help(stdout, stderr, status)
    aggregate_failures do
      expect(status).to be_success
      expect(stderr).to be_empty
      expect(stdout).to include('--config', '--output-dir', '--domain', '--format', '--fail-on-warning')
      expect(stdout).not_to match(forbidden_generate_help_pattern)
    end
  end

  def forbidden_generate_help_pattern
    /\.erdconfig|--strict|--no-strict|--no-fail-on-warning|--skip-fail-on-warning|--allow-partial|--validate|--cache/
  end

  def stub_generator
    result = Struct.new(:stdout, :stderr, :exit_code).new('', '', 0)
    instance_double(RailsMmd::Generate, run: result).tap do |generator|
      allow(RailsMmd::Generate).to receive(:new).and_return(generator)
    end
  end

  def expect_generator_config(generator)
    expect(generator).to have_received(:run).with(
      cli_options: have_attributes(config_path: 'config.yml'),
      fail_on_warning: false
    )
  end

  def expect_generator_fail_on_warning(generator, value)
    expect(generator).to have_received(:run).with(
      cli_options: have_attributes(config_path: 'config.yml'),
      fail_on_warning: value
    )
  end

  def expect_config_not_found(stdout, stderr, status)
    aggregate_failures do
      expect(status.exitstatus).to eq(2)
      expect(stdout).to be_empty
      expect(stderr_diagnostic_code(stderr)).to eq('CONFIG_NOT_FOUND')
      expect(Pathname('docs/rails_mmd')).not_to exist
    end
  end

  def stderr_diagnostic_code(stderr)
    JSON.parse(stderr).fetch('diagnostics').first.fetch('code')
  end
end
