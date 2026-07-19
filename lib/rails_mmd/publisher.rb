# frozen_string_literal: true

require 'json'
require 'rails_mmd/diagnostic_factory'
require 'rails_mmd/output_directory'
require 'rails_mmd/schema_validator'

module RailsMmd
  # Atomically publishes diagnostics, render plans, and Mermaid artifacts.
  # rubocop:disable Metrics/ClassLength
  class Publisher
    Result = Struct.new(:success, :diagnostics, :written_paths, :stderr, keyword_init: true) do
      def success?
        success
      end
    end

    PRE_OUTPUT_FATAL_CODES = %w[
      CONFIG_NOT_FOUND
      CONFIG_SCHEMA_INVALID
      CONFIG_DOMAIN_NOT_FOUND
      OUTPUT_DIRECTORY_INVALID
    ].freeze
    ARTIFACT_KINDS = %w[er class].freeze
    def initialize(project_root:, schema_validator: SchemaValidator.new, diagnostics_factory: DiagnosticFactory.new)
      @output_directory = OutputDirectory.new(project_root: project_root)
      @schema_validator = schema_validator
      @diagnostics_factory = diagnostics_factory
    end

    def pre_output_stderr(diagnostics)
      document = schema_validator.validate_pre_output!(diagnostics)
      "#{JSON.pretty_generate(document)}\n"
    end

    def publish(output_dir:, selected_domain_ids:, diagnostics:, artifacts:)
      return pre_output_fatal_result(diagnostics) if pre_output_fatal?(diagnostics)

      output_resolution = output_directory.resolve(output_dir)
      return invalid_output_result(output_resolution.reason) unless output_resolution.valid?

      publish_inside_output(output_resolution, selected_domain_ids, diagnostics, artifacts)
    rescue StandardError => e
      Result.new(success: false, diagnostics: [output_write_failed(e)], written_paths: [], stderr: nil)
    end

    private

    attr_reader :diagnostics_factory, :output_directory, :schema_validator

    def publish_inside_output(output_resolution, selected_domain_ids, diagnostics, artifacts)
      written_paths = output_directory.publish!(output_resolution, selected_domain_ids: selected_domain_ids) do
        diagnostics = scoped_diagnostics(diagnostics, selected_domain_ids)
        artifacts = scoped_artifacts(artifacts, selected_domain_ids)
        diagnostic_documents = validate_payloads!(diagnostics, artifacts)
        blocked_domains = blocked_domains(selected_domain_ids, diagnostics)
        publish_plan(selected_domain_ids, diagnostic_documents, artifacts, blocked_domains)
      end
      Result.new(success: true, diagnostics: diagnostics, written_paths: written_paths, stderr: nil)
    end

    def validate_payloads!(diagnostics, artifacts)
      schema_validator.validate_publication!(
        diagnostics: diagnostics,
        artifacts: artifacts
      )
    end

    def scoped_diagnostics(diagnostics, selected_domain_ids)
      diagnostics.select do |diagnostic|
        diagnostic.fetch('scope') == 'invocation' || selected_domain_ids.include?(diagnostic_domain_id(diagnostic))
      end
    end

    def scoped_artifacts(artifacts, selected_domain_ids)
      artifacts.slice(*selected_domain_ids)
    end

    def publish_plan(selected_domain_ids, diagnostic_documents, artifacts, blocked_domains)
      plan = diagnostics_plan(diagnostic_documents)
      selected_domain_ids.each do |domain_id|
        next if blocked_domains.include?(domain_id)

        plan.merge!(domain_publish_plan(domain_id, artifacts.fetch(domain_id, {})))
      end
      plan
    end

    def domain_publish_plan(domain_id, artifacts)
      ARTIFACT_KINDS.each_with_object({}) do |kind, plan|
        artifact = artifacts[kind]
        next unless artifact

        plan["#{domain_id}.#{kind}.mmd"] = artifact.fetch(:mermaid)
        plan["#{domain_id}.#{kind}.render_plan.json"] = json_document(artifact.fetch(:render_plan))
      end
    end

    def diagnostics_plan(diagnostic_documents)
      diagnostic_documents.each_with_object({}) do |document, plan|
        name = if document.fetch('scope') == 'global'
                 'global.diagnostics.json'
               else
                 "#{document.fetch('domain_id')}.diagnostics.json"
               end
        plan[name] = json_document(document)
      end
    end

    def diagnostic_domain_id(diagnostic)
      diagnostic.fetch('metadata', {}).fetch('domain_id')
    end

    def blocked_domains(selected_domain_ids, diagnostics)
      return selected_domain_ids if invocation_blocking?(diagnostics)

      diagnostics.each_with_object([]) do |diagnostic, blocked|
        next unless blocking?(diagnostic)
        next if diagnostic.fetch('scope') == 'invocation'

        blocked << diagnostic_domain_id(diagnostic)
      end.uniq
    end

    def invocation_blocking?(diagnostics)
      diagnostics.any? { |diagnostic| diagnostic.fetch('scope') == 'invocation' && blocking?(diagnostic) }
    end

    def blocking?(diagnostic)
      %w[fatal error].include?(diagnostic.fetch('severity'))
    end

    def json_document(payload)
      "#{JSON.pretty_generate(payload)}\n"
    end

    def invalid_output_result(reason)
      diagnostic = diagnostics_factory.build(
        code: 'OUTPUT_DIRECTORY_INVALID',
        message: 'output directory invalid',
        metadata: { field_path: '$.output.directory', reason: reason.to_s }
      )
      Result.new(success: false, diagnostics: [diagnostic], written_paths: [], stderr: pre_output_stderr([diagnostic]))
    end

    def pre_output_fatal?(diagnostics)
      diagnostics.any? { |diagnostic| PRE_OUTPUT_FATAL_CODES.include?(diagnostic.fetch('code')) }
    end

    def pre_output_fatal_result(diagnostics)
      Result.new(success: false, diagnostics: diagnostics, written_paths: [], stderr: pre_output_stderr(diagnostics))
    end

    def output_write_failed(exception)
      diagnostics_factory.build(
        code: 'OUTPUT_WRITE_FAILED',
        message: 'output write failed',
        metadata: { operation: 'write', path: 'output' },
        remediation: { summary: exception.class.name }
      )
    end
  end
  # rubocop:enable Metrics/ClassLength
end
