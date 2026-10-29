# frozen_string_literal: true

require 'thor'
require 'rails_mmd/config'
require 'rails_mmd/generate_command'
require_relative 'version'

module RailsMmd
  # Exposes generation, help, and version commands through Thor.
  class CLI < Thor
    MISSING_OPTION_VALUE = Object.new.freeze
    GENERATE_HELP = <<~HELP
      Usage:
        rails-mmd generate

      Options:
        [--config=CONFIG]            Required YAML file (default: rails_mmd.yml)
        [--output-dir=OUTPUT_DIR]    Project-relative directory (default: docs/rails_mmd)
        [--domain=DOMAIN]            One configured domain ID (default: all domains)
        [--format=FORMAT]            er, class, or both (default: both)
        [--fail-on-warning]          Exit 1 if any warning is emitted (default: false)

      Run from the target Rails application root with bundle exec rails-mmd generate.
      Config output.directory and output.format override the defaults; CLI options take precedence.
    HELP

    package_name 'rails-mmd'
    remove_command :tree
    default_task :help
    check_unknown_options! only: :generate

    def self.exit_on_failure?
      true
    end

    desc 'version', 'Print rails-mmd version'
    map '--version' => :version, '-v' => :version
    def version
      say RailsMmd::VERSION
    end

    desc 'generate', 'Generate Mermaid diagrams from a Rails app'
    method_option :config, type: :string, lazy_default: MISSING_OPTION_VALUE
    method_option :output_dir, type: :string, lazy_default: MISSING_OPTION_VALUE
    method_option :domain, type: :string, lazy_default: MISSING_OPTION_VALUE
    method_option :format, type: :string, lazy_default: MISSING_OPTION_VALUE
    method_option :fail_on_warning, type: :string
    method_option :help, type: :boolean, hide: true, aliases: '-h'
    def generate(*args)
      return say(GENERATE_HELP) if options[:help]
      raise Thor::Error, 'Unexpected arguments. Run rails-mmd generate --help for usage.' unless args.empty?

      result = GenerateCommand.new.run(cli_options: cli_options, fail_on_warning: fail_on_warning?)
      emit_result(result)
    end

    no_commands do
      def cli_options
        missing = options.key(MISSING_OPTION_VALUE)
        raise Thor::Error, "No value provided for option '--#{missing.tr('_', '-')}'" if missing

        Config::CliOptions.new(
          config_path: options[:config],
          output_dir: options[:output_dir],
          domain: options[:domain],
          format: options[:format]
        )
      end

      def emit_result(result)
        warn result.stderr unless result.stderr.empty?
        exit(result.exit_code)
      end

      def fail_on_warning?
        return false if options[:fail_on_warning].nil?
        return false if options[:fail_on_warning] == 'false'
        return true if options[:fail_on_warning] == true
        return true if %w[true fail_on_warning].include?(options[:fail_on_warning]) || options[:fail_on_warning].empty?

        raise Thor::Error, '--fail-on-warning must be true or false'
      end
    end
  end
end
