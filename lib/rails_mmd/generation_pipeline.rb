# frozen_string_literal: true

require 'rails_mmd/constant_resolver'
require 'rails_mmd/domain_resolver'
require 'rails_mmd/diagnostics'
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
      @diagnostics = Diagnostics.new(redactor: redactor)
      @render_plan_builder = render_plan_builder || RenderPlanBuilder.new(redactor: redactor)
      @mermaid_serializer = mermaid_serializer || MermaidSerializer.new(diagnostics: @diagnostics)
    end

    def build(config:)
      resolved, probed, relationships, ir_payload = internal_payloads(config)
      diagnostics = resolved.diagnostics + probed.diagnostics + relationships.diagnostics
      artifacts = render_artifacts(config, ir_payload, diagnostics)
      Result.new(diagnostics: diagnostics, artifacts: artifacts)
    end

    private

    attr_reader :active_record_base, :constant_resolver, :diagnostics, :mermaid_serializer, :redactor,
                :render_plan_builder

    def internal_payloads(config)
      resolved = resolve_domains(config)
      probed = probe_domains(resolved)
      relationships = build_relationships(probed)
      ir_payload = build_ir(config, probed, relationships)
      [resolved, probed, relationships, ir_payload]
    end

    def resolve_domains(config)
      inventory = ModelInventory.new(
        active_record_base: resolved_active_record_base, constant_resolver: constant_resolver, redactor: redactor
      )
      DomainResolver.new(diagnostics: diagnostics).resolve(config: config, inventory_records: inventory.records)
    end

    def probe_domains(resolved)
      SchemaProbe.new(constant_resolver: constant_resolver, diagnostics: diagnostics, redactor: redactor)
                 .probe(domains: resolved.domains)
    end

    def build_relationships(probed)
      RelationshipBuilder.new(constant_resolver: constant_resolver, diagnostics: diagnostics)
                         .build(domains: probed.domains)
    end

    def build_ir(config, probed, relationships)
      IrBuilder.new(attributes: config.output.attributes).build(
        domains: probed.domains, relationship_domains: relationships.domains
      )
    end

    def render_artifacts(config, ir_payload, diagnostics)
      ir_payload.domains.to_h do |domain|
        [domain.domain_id, render_domain_artifacts(config, domain, diagnostics)]
      end
    end

    def render_domain_artifacts(config, domain, diagnostics)
      artifact_kinds(config).each_with_object({}) do |kind, artifacts|
        result = render_plan_for(config, domain, kind, diagnostics)
        diagnostics.concat(result.diagnostics)
        serialized = mermaid_serializer.serialize(render_plan: result.payload)
        diagnostics.concat(serialized.diagnostics)
        next unless serialized.diagnostics.empty?

        artifacts[kind] = { render_plan: result.payload, mermaid: serialized.text }
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
