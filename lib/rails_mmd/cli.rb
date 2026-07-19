# frozen_string_literal: true

require 'thor'
require 'rails_mmd/config'
require 'rails_mmd/generate_command'
require_relative 'version'

module RailsMmd
  # Minimal Thor shell for smokeable help and version output.
  class CLI < Thor
    GENERATE_HELP = <<~HELP
      Usage:
        rails-mmd generate

      Options:
        [--config=CONFIG]
        [--output-dir=OUTPUT_DIR]
        [--domain=DOMAIN]
        [--format=FORMAT]
        [--fail-on-warning]

      Generate Mermaid diagrams from a Rails app
    HELP

    package_name 'rails-mmd'
    remove_command :tree
    default_task :help

    def self.exit_on_failure?
      true
    end

    desc 'version', 'Print rails-mmd version'
    map '--version' => :version, '-v' => :version
    def version
      say RailsMmd::VERSION
    end

    desc 'generate', 'Generate Mermaid diagrams from a Rails app'
    method_option :config, type: :string
    method_option :output_dir, type: :string
    method_option :domain, type: :string
    method_option :format, type: :string
    method_option :fail_on_warning, type: :string
    def generate(*args)
      return say(GENERATE_HELP) if args.include?('--help')

      result = GenerateCommand.new.run(cli_options: cli_options, fail_on_warning: fail_on_warning?)
      emit_result(result)
    end

    no_commands do
      def cli_options
        Config::CliOptions.new(
          config_path: options[:config],
          output_dir: options[:output_dir],
          domain: options[:domain],
          format: options[:format]
        )
      end

      def emit_result(result)
        print result.stdout unless result.stdout.empty?
        warn result.stderr unless result.stderr.empty?
        exit(result.exit_code)
      end

      def fail_on_warning?
        return false if options[:fail_on_warning].nil?
        return true if options[:fail_on_warning] == true
        return true if %w[true fail_on_warning].include?(options[:fail_on_warning]) || options[:fail_on_warning].empty?

        false
      end
    end
  end
end
