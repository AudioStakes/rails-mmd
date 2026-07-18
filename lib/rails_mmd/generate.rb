# frozen_string_literal: true

require 'rails_mmd/config'
require 'rails_mmd/domain_resolver'
require 'rails_mmd/exit_policy'
require 'rails_mmd/ir_builder'
require 'rails_mmd/mermaid_serializer'
require 'rails_mmd/model_inventory'
require 'rails_mmd/publisher'
require 'rails_mmd/rails_loader'
require 'rails_mmd/relationship_builder'
require 'rails_mmd/render_plan_builder'
require 'rails_mmd/schema_probe'

module RailsMmd
  # Coordinates the P0 generate pipeline behind the Thor command.
  # rubocop:disable Metrics/ClassLength
  class Generate
    Result = Struct.new(:exit_code, :stdout, :stderr, :diagnostics, keyword_init: true) do
      def success?
        exit_code.zero?
      end
    end

    def initialize(project_root: Dir.pwd, dependencies: {})
      @project_root = Pathname(project_root).expand_path
      @dependencies = dependencies
    end

    def run(cli_options:, fail_on_warning: false)
      config_result = config_loader.load(cli_options: cli_options)
      return pre_output_result(config_result.diagnostics, config_result.exit_code) unless config_result.success?

      run_pipeline(config_result.config, fail_on_warning)
    rescue StandardError => e
      internal_error_result(e)
    end

    private

    attr_reader :dependencies, :project_root

    def run_pipeline(config, fail_on_warning)
      rails_result = rails_loader.boot
      return pre_output_result(rails_result.diagnostics, rails_result.exit_code) unless rails_result.success?

      diagnostics, artifacts = build_artifacts(config, rails_result.application)
      publish_result(config, diagnostics, artifacts, fail_on_warning)
    end

    def build_artifacts(config, application)
      resolved, probed, relationships, ir_payload = internal_payloads(config, application)
      diagnostics = resolved.diagnostics + probed.diagnostics + relationships.diagnostics
      [diagnostics, render_artifacts(config, ir_payload, diagnostics)]
    end

    def internal_payloads(config, application)
      inventory = inventory_for(application)
      resolved = domain_resolver.resolve(config: config, inventory_records: inventory.records)
      probed = schema_probe.probe(
        domains: resolved.domains,
        inventory_records: inventory.records,
        owned_domain_ids_by_constant: resolved.owned_domain_ids_by_constant
      )
      relationships = relationship_builder.build(domains: probed.domains)
      ir_payload = ir_builder(config).build(domains: probed.domains, relationship_domains: relationships.domains)
      [resolved, probed, relationships, ir_payload]
    end

    def render_artifacts(config, ir_payload, diagnostics)
      ir_payload.domains.to_h do |domain|
        [domain.domain_id, render_domain_artifacts(config, domain, diagnostics)]
      end
    end

    def render_domain_artifacts(config, domain, diagnostics)
      artifact_kinds(config).each_with_object({}) do |kind, artifacts|
        render_plan_result = render_plan_for(config, domain, kind, diagnostics)
        render_plan = render_plan_result.payload
        diagnostics.concat(render_plan_result.diagnostics)
        serialized = mermaid_serializer.serialize(render_plan: render_plan)
        diagnostics.concat(serialized.diagnostics)
        next unless serialized.diagnostics.empty?

        artifacts[kind] = { render_plan: render_plan, mermaid: serialized.text }
      end
    end

    def render_plan_for(config, domain, kind, diagnostics)
      render_plan_builder.build(
        ir: domain.payload,
        artifact_kind: kind,
        direction: config.output.direction,
        attributes: config.output.attributes,
        available_diagnostic_ids: diagnostics.map { |diagnostic| diagnostic.fetch('diagnostic_id') }
      )
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

    def artifact_kinds(config)
      config.output.format == 'both' ? %w[er class] : [config.output.format]
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

    def config_loader
      dependencies.fetch(:config_loader) { Config.new(project_root: project_root) }
    end

    def rails_loader
      dependencies.fetch(:rails_loader) { RailsLoader.new(project_root: project_root) }
    end

    def inventory_for(_application)
      return dependencies.fetch(:model_inventory) if dependencies.key?(:model_inventory)

      active_record_base = dependencies.fetch(:active_record_base) { Object.const_get(:ActiveRecord).const_get(:Base) }
      ModelInventory.new(active_record_base: active_record_base)
    end

    def domain_resolver
      dependencies.fetch(:domain_resolver) { DomainResolver.new }
    end

    def schema_probe
      dependencies.fetch(:schema_probe) { SchemaProbe.new(model_resolver: model_resolver) }
    end

    def relationship_builder
      dependencies.fetch(:relationship_builder) { RelationshipBuilder.new(model_resolver: model_resolver) }
    end

    def ir_builder(config)
      dependencies.fetch(:ir_builder) { IrBuilder.new(attributes: config.output.attributes) }
    end

    def render_plan_builder
      dependencies.fetch(:render_plan_builder) { RenderPlanBuilder.new }
    end

    def mermaid_serializer
      dependencies.fetch(:mermaid_serializer) { MermaidSerializer.new }
    end

    def publisher
      dependencies.fetch(:publisher) { Publisher.new(project_root: project_root) }
    end

    def diagnostics_factory
      dependencies.fetch(:diagnostics_factory) { Diagnostics.new }
    end

    def model_resolver
      dependencies.fetch(:model_resolver) do
        lambda { |constant|
          constant.split('::').reduce(Object) do |ns, name|
            ns.const_get(name, false)
          end
        }
      end
    end
  end
  # rubocop:enable Metrics/ClassLength
end
