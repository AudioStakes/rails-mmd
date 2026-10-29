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

    it 'does not expose unsupported option names' do
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

  it 'passes all supported generate options through Thor in process' do
    generator = stub_generator

    expect { described_class.start(generate_args) }.to raise_error(SystemExit)
    expect_generator_options(generator)
  end

  it 'passes a false fail-on-warning value through Thor in process' do
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
    %w[config output-dir domain format].each do |option|
      it "rejects --#{option} without a value before generation" do
        generator = stub_generator

        expect_rejected_arguments(["--#{option}"], generator)
      end
    end

    it 'accepts an explicit output directory matching the option name' do
      generator = stub_generator

      expect { described_class.start(%w[generate --output-dir output_dir]) }.to raise_error(SystemExit)
      expect_generator_output_directory(generator)
    end

    [%w[--fomat er], %w[unexpected], %w[--fail-on-warning=treu]].each do |arguments|
      it "rejects invalid arguments #{arguments.inspect} before generation" do
        generator = stub_generator

        expect_rejected_arguments(arguments, generator)
      end
    end

    it 'prints supported options in command help' do
      stdout, stderr, status = run_cli('generate', '--help')

      expect_generate_help(stdout, stderr, status)
    end

    it 'returns sanitized CONFIG_NOT_FOUND diagnostics when no config exists' do
      stdout, stderr, status = run_cli('generate')

      expect_config_not_found(stdout, stderr, status)
    end
  end

  def expect_rejected_arguments(arguments, generator)
    aggregate_failures do
      expect do
        expect { described_class.start(['generate', *arguments]) }.to raise_error(SystemExit) do |error|
          expect(error).to have_attributes(status: 1)
        end
      end.to output(/Unknown switches|Unexpected arguments|must be true or false|No value provided/).to_stderr
      expect(generator).not_to have_received(:run)
    end
  end

  def expect_generator_output_directory(generator)
    expect(generator).to have_received(:run).with(
      cli_options: have_attributes(output_dir: 'output_dir'),
      fail_on_warning: false
    )
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
    Regexp.union(
      /\.erdconfig/, /--strict/, /--no-strict/, /--no-fail-on-warning/, /--skip-fail-on-warning/,
      /--fail-on-warning=/, /--allow-partial/, /--validate/, /--cache/
    )
  end

  def stub_generator
    result = Struct.new(:stderr, :exit_code).new('', 0)
    instance_double(RailsMmd::GenerateCommand, run: result).tap do |generator|
      allow(RailsMmd::GenerateCommand).to receive(:new).and_return(generator)
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

  def expect_generator_options(generator)
    expect(generator).to have_received(:run).with(
      cli_options: have_attributes(
        config_path: 'config.yml',
        output_dir: 'docs/diagrams',
        domain: 'billing',
        format: 'class'
      ),
      fail_on_warning: true
    )
  end

  def generate_args
    %w[generate --config config.yml --output-dir docs/diagrams --domain billing --format class --fail-on-warning]
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
