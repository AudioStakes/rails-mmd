# frozen_string_literal: true

require 'rails_mmd/config'
require 'rails_mmd/exit_policy'
require 'rails_mmd/generation_pipeline'
require 'rails_mmd/publisher'
require 'rails_mmd/rails_loader'
require 'rails_mmd/redactor'

module RailsMmd
  # Coordinates the P0 generate pipeline behind the Thor command.
  # @api private
  class Generate
    Result = Struct.new(:exit_code, :stdout, :stderr, :diagnostics, keyword_init: true) do
      def success?
        exit_code.zero?
      end
    end

    def initialize(project_root: Dir.pwd, rails_loader: nil, pipeline: nil)
      @project_root = Pathname(project_root).expand_path
      @rails_loader = rails_loader
      @pipeline = pipeline
    end

    def run(cli_options:, fail_on_warning: false)
      config_result = Config.new(project_root: project_root, redactor: redactor).load(cli_options: cli_options)
      return pre_output_result(config_result.diagnostics, config_result.exit_code) unless config_result.success?

      run_pipeline(config_result.config, fail_on_warning)
    rescue StandardError => e
      internal_error_result(e)
    end

    private

    attr_reader :project_root

    def run_pipeline(config, fail_on_warning)
      rails_result = rails_loader.boot
      return pre_output_result(rails_result.diagnostics, rails_result.exit_code) unless rails_result.success?

      result = pipeline.build(config: config)
      publish_result(config, result.diagnostics, result.artifacts, fail_on_warning)
    end

    def publish_result(config, diagnostics, artifacts, fail_on_warning)
      result = publisher.publish(
        output_dir: config.output.directory,
        selected_domain_ids: config.selected_domain_ids,
        diagnostics: diagnostics,
        artifacts: artifacts
      )
      result_for_publish(result, fail_on_warning)
    end

    def result_for_publish(result, fail_on_warning)
      Result.new(
        exit_code: publish_exit_code(result, fail_on_warning),
        stdout: '',
        stderr: publish_stderr(result),
        diagnostics: result.diagnostics
      )
    end

    def publish_exit_code(result, fail_on_warning)
      ExitPolicy.exit_code(result.diagnostics, fail_on_warning: fail_on_warning)
    end

    def publish_stderr(result)
      return result.stderr.to_s unless result.stderr.to_s.empty?
      return '' if result.success?

      publisher.pre_output_stderr(result.diagnostics)
    end

    def pre_output_result(diagnostics, exit_code)
      Result.new(exit_code: exit_code, stdout: '', stderr: publisher.pre_output_stderr(diagnostics),
                 diagnostics: diagnostics)
    end

    def internal_error_result(exception)
      diagnostic = diagnostics_factory.build(
        code: 'INTERNAL_ERROR',
        message: 'internal error',
        metadata: diagnostics_factory.exception_metadata(exception)
      )
      Result.new(exit_code: 99, stdout: '', stderr: publisher.pre_output_stderr([diagnostic]),
                 diagnostics: [diagnostic])
    end

    def rails_loader
      @rails_loader ||= RailsLoader.new(project_root: project_root, diagnostics: diagnostics_factory)
    end

    def publisher
      @publisher ||= Publisher.new(project_root: project_root, diagnostics_factory: diagnostics_factory)
    end

    def diagnostics_factory
      @diagnostics_factory ||= Diagnostics.new(redactor: redactor)
    end

    def redactor
      @redactor ||= Redactor.new(project_root: project_root)
    end

    def pipeline
      @pipeline ||= GenerationPipeline.new(redactor: redactor)
    end
  end
end
