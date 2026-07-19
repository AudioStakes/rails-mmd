# frozen_string_literal: true

require 'rails_mmd/constant_resolver'
require 'rails_mmd/domain_resolver'
require 'rails_mmd/diagnostic_factory'
require 'rails_mmd/ir_builder'
require 'rails_mmd/mermaid_serializer'
require 'rails_mmd/model_inventory'
require 'rails_mmd/relationship_builder'
require 'rails_mmd/render_plan_builder'
require 'rails_mmd/redactor'
require 'rails_mmd/schema_probe'

module RailsMmd
  # Builds every selected-domain artifact behind one in-process interface.
  class GenerationPipeline
    Result = Struct.new(:diagnostics, :artifacts, keyword_init: true)

    def initialize(active_record_base: nil, constant_resolver: ConstantResolver.new, redactor: Redactor.new,
                   render_plan_builder: nil,
                   mermaid_serializer: nil)
      @active_record_base = active_record_base
      @constant_resolver = ConstantResolver.wrap(constant_resolver)
      @redactor = redactor
      @diagnostic_factory = DiagnosticFactory.new(redactor: redactor)
      @render_plan_builder = render_plan_builder || RenderPlanBuilder.new(redactor: redactor)
      @mermaid_serializer = mermaid_serializer || MermaidSerializer.new(diagnostics: @diagnostic_factory)
    end

    def generate(config:)
      domain_resolution, schema_probe_result, relationship_result, ir_payload = build_stage_results(config)
      diagnostics = domain_resolution.diagnostics + schema_probe_result.diagnostics + relationship_result.diagnostics
      artifacts = render_artifacts(config, ir_payload, diagnostics)
      Result.new(diagnostics: diagnostics, artifacts: artifacts)
    end

    # Backward-compatible name for the original generation seam.
    def build(config:) = generate(config: config)

    private

    attr_reader :active_record_base, :constant_resolver, :diagnostic_factory, :mermaid_serializer, :redactor,
                :render_plan_builder

    def build_stage_results(config)
      domain_resolution = resolve_domains(config)
      schema_probe_result = probe_domains(domain_resolution)
      relationship_result = build_relationships(schema_probe_result)
      ir_payload = build_ir(config, schema_probe_result, relationship_result)
      [domain_resolution, schema_probe_result, relationship_result, ir_payload]
    end

    def resolve_domains(config)
      inventory = ModelInventory.new(
        active_record_base: resolved_active_record_base, constant_resolver: constant_resolver, redactor: redactor
      )
      DomainResolver.new(diagnostics: diagnostic_factory).resolve(config: config, inventory_records: inventory.records)
    end

    def probe_domains(domain_resolution)
      SchemaProbe.new(constant_resolver: constant_resolver, diagnostics: diagnostic_factory, redactor: redactor)
                 .probe(domains: domain_resolution.domains)
    end

    def build_relationships(schema_probe_result)
      RelationshipBuilder.new(constant_resolver: constant_resolver, diagnostics: diagnostic_factory)
                         .build(domains: schema_probe_result.domains)
    end

    def build_ir(config, schema_probe_result, relationship_result)
      IrBuilder.new(attributes: config.output.attributes).build(
        domains: schema_probe_result.domains, relationship_domains: relationship_result.domains
      )
    end

    def render_artifacts(config, ir_payload, diagnostics)
      ir_payload.domains.to_h do |domain|
        [domain.domain_id, render_domain_artifacts(config, domain, diagnostics)]
      end
    end

    def render_domain_artifacts(config, domain, diagnostics)
      artifact_kinds(config).each_with_object({}) do |kind, artifacts|
        render_plan_result = render_plan_for(config, domain, kind, diagnostics)
        diagnostics.concat(render_plan_result.diagnostics)
        serialization_result = mermaid_serializer.serialize(render_plan: render_plan_result.payload)
        diagnostics.concat(serialization_result.diagnostics)
        next unless serialization_result.diagnostics.empty?

        artifacts[kind] = { render_plan: render_plan_result.payload, mermaid: serialization_result.text }
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

    def artifact_kinds(config)
      config.output.format == 'both' ? %w[er class] : [config.output.format]
    end

    def resolved_active_record_base
      active_record_base || Object.const_get(:ActiveRecord).const_get(:Base)
    end
  end
end
