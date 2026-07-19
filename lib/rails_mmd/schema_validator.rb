# frozen_string_literal: true

require 'json'
require 'json_schemer'
require 'rails_mmd/canonical_json'
require 'rails_mmd/ordering'

module RailsMmd
  # Validates payloads against repository JSON Schemas.
  class SchemaValidator
    class InvalidPayload < ArgumentError; end

    SCHEMA_FILES = {
      config: 'config.schema.json',
      diagnostics: 'diagnostics.schema.json',
      ir: 'ir.schema.json',
      render_plan: 'render_plan.schema.json'
    }.freeze

    def initialize(schema_root: Pathname(__dir__).join('../../schemas').expand_path)
      @schema_root = Pathname(schema_root)
      @schemas = {}
    end

    def valid?(schema_name, payload)
      schema(schema_name).valid?(payload)
    end

    def errors(schema_name, payload)
      schema(schema_name).validate(payload).to_a
    end

    def validate!(schema_name, payload)
      return payload if valid?(schema_name, payload)

      raise InvalidPayload, "#{schema_name.to_s.tr('_', ' ')} schema invalid"
    end

    def validate_render_plan!(render_plan)
      validate!(:render_plan, render_plan)
    end

    def validate_pre_output!(diagnostics)
      validate!(:diagnostics, diagnostic_document('global', nil, diagnostics))
    end

    def validate_publication!(diagnostics:, artifacts:)
      diagnostic_documents = diagnostic_documents(diagnostics)
      diagnostic_documents.each { |document| validate!(:diagnostics, document) }
      each_render_plan(artifacts) { |render_plan| validate_render_plan!(render_plan) }
      validate_diagnostic_refs!(diagnostic_documents, artifacts)
      diagnostic_documents
    end

    private

    attr_reader :schema_root, :schemas

    def schema(schema_name)
      key = schema_name.to_sym
      schemas[key] ||= JSONSchemer.schema(JSON.parse(schema_root.join(SCHEMA_FILES.fetch(key)).read))
    end

    def each_render_plan(artifacts)
      artifacts.each_value do |domain_artifacts|
        domain_artifacts.each_value { |artifact| yield artifact.fetch(:render_plan) }
      end
    end

    def validate_diagnostic_refs!(diagnostic_documents, artifacts)
      diagnostic_ids = diagnostic_ids_by_domain(diagnostic_documents)
      artifacts.each do |domain_id, domain_artifacts|
        allowed_ids = diagnostic_ids.fetch(nil, []) + diagnostic_ids.fetch(domain_id, [])
        each_render_plan(domain_id => domain_artifacts) do |render_plan|
          unresolved = render_plan.fetch('diagnostic_ids') - allowed_ids
          raise InvalidPayload, 'render plan diagnostic_ids unresolved' unless unresolved.empty?
        end
      end
    end

    def diagnostic_ids_by_domain(diagnostic_documents)
      diagnostic_documents.each_with_object({}) do |document, ids|
        domain_id = document.fetch('scope') == 'global' ? nil : document.fetch('domain_id')
        ids[domain_id] ||= []
        ids[domain_id].concat(document.fetch('diagnostics').map { |diagnostic| diagnostic.fetch('diagnostic_id') })
      end
    end

    def diagnostic_documents(diagnostics)
      groups = diagnostics.group_by do |diagnostic|
        diagnostic.fetch('scope') == 'invocation' ? ['global', nil] : ['domain', diagnostic_domain_id(diagnostic)]
      end
      groups.map do |(scope, domain_id), items|
        diagnostic_document(scope, domain_id, items)
      end
    end

    def diagnostic_document(scope, domain_id, diagnostics)
      payload = {
        'schema_version' => 1,
        'scope' => scope,
        'domain_id' => domain_id,
        'diagnostics' => Ordering.sort_diagnostics(diagnostics),
        'digest_sha256' => nil
      }
      payload.merge('digest_sha256' => CanonicalJson.digest_sha256(payload))
    end

    def diagnostic_domain_id(diagnostic)
      diagnostic.fetch('metadata', {}).fetch('domain_id')
    end
  end
end
