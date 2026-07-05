# frozen_string_literal: true

require 'rails_mmd/canonical_json'

module RailsMmd
  # Normalizes selected schema entities and relationships into closed IR payloads.
  class IrBuilder
    DomainResult = Struct.new(:domain_id, :payload, keyword_init: true)
    Result = Struct.new(:domains, keyword_init: true)

    def initialize(attributes: :keys)
      @attributes = attributes.to_sym
    end

    def build(domains:, relationship_domains:)
      relationships_by_domain = relationship_domains.to_h { |domain| [domain.domain_id, domain] }
      results = domains.map do |domain|
        relationship_domain = relationships_by_domain.fetch(domain.domain_id, nil)
        DomainResult.new(domain_id: domain.domain_id, payload: payload_for(domain, relationship_domain))
      end

      Result.new(domains: results)
    end

    private

    attr_reader :attributes

    def payload_for(domain, relationship_domain)
      payload = payload_without_digest(domain, relationship_domain)
      payload.merge('digest_sha256' => CanonicalJson.digest_sha256(payload))
    end

    def payload_without_digest(domain, relationship_domain)
      {
        'schema_version' => 1,
        'domain_id' => domain.domain_id,
        'entities' => entities_payload(domain, relationship_domain),
        'relationships' => relationships_payload(relationship_domain),
        'diagnostic_ids' => diagnostic_ids(domain, relationship_domain),
        'digest_sha256' => nil
      }
    end

    def entities_payload(domain, relationship_domain)
      payloads = domain.entities.map { |entity| entity_payload(entity, relationship_domain) }

      payloads.sort_by { |entity| entity.fetch('entity_id') }
    end

    def entity_payload(entity, relationship_domain)
      {
        'entity_id' => entity_id(entity),
        'ruby_constant' => entity.ruby_constant,
        'table_name' => entity.table_name,
        'attributes' => attributes_payload(entity, relationship_domain)
      }
    end

    def attributes_payload(entity, relationship_domain)
      return [] if attributes == :none

      names = [[entity.primary_key, 'primary_key']]
      names.concat(foreign_key_names(entity, relationship_domain).map { |name| [name, 'foreign_key'] })
      payloads = names.compact.uniq.map do |name, role|
        { 'attribute_id' => "#{entity_id(entity)}/attributes/#{name}", 'name' => name, 'role' => role }
      end

      payloads.sort_by do |attribute|
        [attribute.fetch('role') == 'primary_key' ? 0 : 1, attribute.fetch('attribute_id')]
      end
    end

    def foreign_key_names(entity, relationship_domain)
      return [] unless relationship_domain

      relationship_domain.relationships.filter_map do |relationship|
        relationship.owner_foreign_key_column if relationship.owner_entity_id == entity_id(entity)
      end
    end

    def relationships_payload(relationship_domain)
      return [] unless relationship_domain

      payloads = relationship_domain.relationships.map { |relationship| relationship_payload(relationship) }

      payloads.sort_by { |relationship| relationship.fetch('relationship_id') }
    end

    def relationship_payload(relationship)
      {
        'relationship_id' => relationship.relationship_id,
        'owner_entity_id' => relationship.owner_entity_id,
        'target_entity_id' => relationship.target_entity_id,
        'association_name' => relationship.association_name,
        'owner_cardinality' => relationship.owner_cardinality,
        'target_cardinality' => relationship.target_cardinality
      }
    end

    def diagnostic_ids(domain, relationship_domain)
      ids = domain.diagnostics.map { |diagnostic| diagnostic.fetch('diagnostic_id') }
      if relationship_domain
        ids.concat(relationship_domain.diagnostics.map do |diagnostic|
          diagnostic.fetch('diagnostic_id')
        end)
      end
      ids.uniq.sort
    end

    def entity_id(entity)
      "entities/#{entity.table_name}"
    end
  end
end
