# frozen_string_literal: true

require 'fileutils'
require 'json'
require 'tmpdir'
require 'rails_mmd/diagnostics'
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
    MANAGED_PATH_PATTERN =
      /\A(?:global\.diagnostics|[a-z][a-z0-9_]*\.(?:diagnostics|er|class)(?:\.render_plan)?)\.(?:json|mmd)\z/

    def initialize(project_root:, schema_validator: SchemaValidator.new, diagnostics_factory: Diagnostics.new)
      @project_root = Pathname(project_root).expand_path
      @output_directory = OutputDirectory.new(project_root: @project_root)
      @schema_validator = schema_validator
      @diagnostics_factory = diagnostics_factory
    end

    def pre_output_stderr(diagnostics)
      document = schema_validator.validate_pre_output!(diagnostics)
      "#{JSON.pretty_generate(document)}\n"
    end

    def publish(output_dir:, selected_domain_ids:, diagnostics:, artifacts:)
      return pre_output_fatal_result(diagnostics) if pre_output_fatal?(diagnostics)

      result = output_directory.resolve(output_dir)
      return invalid_output_result(result.reason) unless result.valid?

      publish_inside_output(result, selected_domain_ids, diagnostics, artifacts)
    rescue StandardError => e
      Result.new(success: false, diagnostics: [output_write_failed(e)], written_paths: [], stderr: nil)
    end

    private

    attr_reader :diagnostics_factory, :output_directory, :project_root, :schema_validator

    def publish_inside_output(result, selected_domain_ids, diagnostics, artifacts)
      prepare_output_directory(result.path)
      diagnostics = scoped_diagnostics(diagnostics, selected_domain_ids)
      artifacts = scoped_artifacts(artifacts, selected_domain_ids)
      diagnostic_documents = validate_payloads!(diagnostics, artifacts)
      blocked_domains = blocked_domains(selected_domain_ids, diagnostics)
      plan = publish_plan(selected_domain_ids, diagnostic_documents, artifacts, blocked_domains)
      write_plan(result.path, plan, selected_domain_ids)
      Result.new(success: true, diagnostics: diagnostics, written_paths: plan.keys.sort, stderr: nil)
    end

    def prepare_output_directory(path)
      path.mkpath
      ensure_inside_project_root!(path)
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

    def write_plan(output_path, plan, selected_domain_ids)
      ensure_inside_project_root!(output_path)
      ensure_safe_replacement_set!(output_path, plan, selected_domain_ids)
      Dir.mktmpdir('.rails-mmd-', output_path.to_s) do |tmp|
        tmp_path = Pathname(tmp)
        plan.each { |relative_path, content| tmp_path.join(relative_path).write(content) }
        ensure_inside_project_root!(output_path)
        ensure_safe_replacement_set!(output_path, plan, selected_domain_ids)
        replace_plan_files(output_path, tmp_path, plan, selected_domain_ids)
      end
    end

    def replace_plan_files(output_path, tmp_path, plan, selected_domain_ids)
      Dir.mktmpdir('.rails-mmd-backup-', output_path.to_s) do |backup|
        backup_path = Pathname(backup)
        backup_existing_files(output_path, backup_path, selected_domain_ids)
        move_plan_files(output_path, tmp_path, plan)
      rescue StandardError
        rollback_replacement(output_path, backup_path, plan)
        raise
      end
    end

    def backup_existing_files(output_path, backup_path, selected_domain_ids)
      scoped_managed_paths(output_path, selected_domain_ids).each do |path|
        ensure_safe_target!(output_path, path.basename.to_s)
        FileUtils.mv(path.to_s, backup_path.join(path.basename).to_s)
      end
    end

    def move_plan_files(output_path, tmp_path, plan)
      plan.each_key { |relative_path| replace_file(output_path, tmp_path, relative_path) }
    end

    def rollback_replacement(output_path, backup_path, plan)
      plan.each_key do |relative_path|
        target = output_path.join(relative_path)
        target.delete if target.file? && !target.symlink?
      end
      backup_path.children.each do |path|
        ensure_safe_target!(output_path, path.basename.to_s)
        FileUtils.mv(path.to_s, output_path.join(path.basename).to_s)
      end
    end

    def ensure_safe_replacement_set!(output_path, plan, selected_domain_ids)
      scoped_managed_paths(output_path, selected_domain_ids).each do |path|
        ensure_safe_target!(output_path, path.basename.to_s)
      end
      plan.each_key { |relative_path| ensure_safe_target!(output_path, relative_path) }
    end

    def scoped_managed_paths(output_path, selected_domain_ids)
      output_path.children.select do |path|
        managed_path?(path) && scoped_managed_path?(path.basename.to_s, selected_domain_ids)
      end
    end

    def managed_path?(path)
      path.basename.to_s.match?(MANAGED_PATH_PATTERN)
    end

    def scoped_managed_path?(name, selected_domain_ids)
      return true if name == 'global.diagnostics.json'

      selected_domain_ids.any? { |domain_id| name.start_with?("#{domain_id}.") }
    end

    def replace_file(output_path, tmp_path, relative_path)
      ensure_inside_project_root!(output_path)
      ensure_safe_target!(output_path, relative_path)
      FileUtils.mv(tmp_path.join(relative_path).to_s, output_path.join(relative_path).to_s)
    end

    def ensure_safe_target!(output_path, relative_path)
      target = output_path.join(relative_path)
      raise ArgumentError, 'output target is symlink' if target.symlink?
      raise ArgumentError, 'output target is not a regular file' if target.exist? && !target.file?

      ensure_inside_project_root!(target.parent)
    end

    def ensure_inside_project_root!(path)
      relative = path.realpath.relative_path_from(project_root.realpath).to_s
      raise ArgumentError, 'output path escapes project root' if relative.start_with?('..')
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
