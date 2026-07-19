# frozen_string_literal: true

require 'rails_mmd/canonical_json'
require 'rails_mmd/relationship_metadata'

module RailsMmd
  # Normalizes selected schema entities and relationships into closed IR payloads.
  # rubocop:disable Metrics/AbcSize, Metrics/ClassLength, Metrics/MethodLength
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
      physical_entity_ids = domain.entities.map { |entity| entity_id(entity) }
      ensure_unique_ids!(physical_entity_ids, 'physical entity_id')
      subtype_entities = validated_sti_subtypes(domain)
      base_metadata = base_metadata_by_entity_id(subtype_entities)

      {
        'schema_version' => 5,
        'domain_id' => domain.domain_id,
        'entities' => entities_payload(domain, relationship_domain, subtype_entities, base_metadata),
        'relationships' => relationships_payload(relationship_domain, physical_entity_ids),
        'diagnostic_ids' => diagnostic_ids(domain, relationship_domain),
        'digest_sha256' => nil
      }
    end

    def entities_payload(domain, relationship_domain, subtype_entities, base_metadata)
      payloads = domain.entities.map do |entity|
        entity_payload(entity, relationship_domain, base_metadata[entity_id(entity)])
      end
      payloads.concat(subtype_entities.map { |subtype| sti_subtype_payload(subtype) })

      payloads.sort_by { |entity| entity.fetch('entity_id') }
    end

    def entity_payload(entity, relationship_domain, metadata)
      payload = {
        'entity_id' => entity_id(entity),
        'ruby_constant' => entity.ruby_constant,
        'table_name' => entity.table_name,
        'attributes' => attributes_payload(entity, relationship_domain)
      }
      payload['metadata'] = metadata if metadata
      payload
    end

    def sti_subtype_payload(subtype)
      {
        'entity_id' => subtype.entity_id,
        'ruby_constant' => subtype.ruby_constant,
        'table_name' => subtype.table_name,
        'attributes' => [],
        'metadata' => {
          'kind' => 'sti_subtype',
          'base_entity_id' => subtype.base_entity_id,
          'parent_entity_id' => subtype.parent_entity_id,
          'inheritance_column' => subtype.inheritance_column,
          'sti_name' => subtype.sti_name
        }
      }
    end

    def attributes_payload(entity, relationship_domain)
      return [] if attributes == :none

      roles_by_name = Hash.new { |roles, name| roles[name] = [] }
      entity.primary_key_columns.each { |name| roles_by_name[name] << :primary }
      foreign_key_names(entity, relationship_domain).each { |name| roles_by_name[name] << :foreign }
      payloads = roles_by_name.map do |name, roles|
        role = attribute_role(roles)
        { 'attribute_id' => "#{entity_id(entity)}/attributes/#{name}", 'name' => name, 'role' => role,
          'type' => column_type(entity, name) }
      end

      payloads.sort_by do |attribute|
        [attribute.fetch('role') == 'foreign_key' ? 1 : 0, attribute.fetch('attribute_id')]
      end
    end

    def attribute_role(roles)
      case roles.uniq.sort
      when [:primary]
        'primary_key'
      when [:foreign]
        'foreign_key'
      when %i[foreign primary]
        'primary_foreign_key'
      else
        raise ArgumentError, "unsupported attribute roles: #{roles.inspect}"
      end
    end

    def foreign_key_names(entity, relationship_domain)
      return [] unless relationship_domain

      relationship_domain.relationships.flat_map do |relationship|
        holder_id = relationship.foreign_key_holder_entity_id || relationship.owner_entity_id
        next [] unless holder_id == entity_id(entity)

        Array(relationship.foreign_key_columns) + [relationship.foreign_type_column].compact
      end
    end

    def column_type(entity, name)
      entity.columns.find { |column| column.name == name }&.type&.to_s || 'unknown'
    end

    def relationships_payload(relationship_domain, physical_entity_ids)
      return [] unless relationship_domain

      validate_relationship_endpoints!(relationship_domain, physical_entity_ids)
      payloads = relationship_domain.relationships.map { |relationship| relationship_payload(relationship) }

      payloads.sort_by { |relationship| relationship.fetch('relationship_id') }
    end

    def relationship_payload(relationship)
      payload = {
        'relationship_id' => relationship.relationship_id,
        'owner_entity_id' => relationship.owner_entity_id,
        'target_entity_id' => relationship.target_entity_id,
        'association_name' => relationship.association_name,
        'owner_cardinality' => relationship.owner_cardinality,
        'target_cardinality' => relationship.target_cardinality
      }
      metadata = RelationshipMetadata.public_payload(relationship.metadata)
      payload['metadata'] = metadata if metadata
      payload
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

    def validated_sti_subtypes(domain)
      physical_entities = domain.entities.to_h { |entity| [entity_id(entity), entity] }
      subtypes = Array(domain.respond_to?(:sti_subtypes) ? domain.sti_subtypes : nil)
      ensure_unique_ids!(subtypes.map(&:entity_id), 'sti subtype entity_id')
      subtypes_by_id = subtypes.to_h { |subtype| [subtype.entity_id, subtype] }

      validated = subtypes.map do |subtype|
        validate_sti_subtype!(subtype, physical_entities, subtypes_by_id)
        subtype
      end
      validate_sti_cycles!(validated, subtypes_by_id)
      validated.sort_by(&:entity_id)
    end

    def validate_sti_cycles!(subtypes, subtypes_by_id)
      subtypes.each do |subtype|
        visited = {}
        current = subtype
        while current
          raise ArgumentError, "sti inheritance cycle: #{subtype.entity_id}" if visited[current.entity_id]

          visited[current.entity_id] = true
          current = subtypes_by_id[current.parent_entity_id]
        end
      end
    end

    def validate_sti_subtype!(subtype, physical_entities, subtypes_by_id)
      base_entity = physical_entities.fetch(subtype.base_entity_id) do
        raise ArgumentError, "sti subtype base missing: #{subtype.entity_id}"
      end
      parent_entity = resolve_parent_entity(subtype, physical_entities, subtypes_by_id)
      if base_entity.table_name != subtype.table_name
        raise ArgumentError, "sti subtype base table mismatch: #{subtype.entity_id}"
      end
      if parent_entity.fetch(:base_entity_id) != subtype.base_entity_id
        raise ArgumentError, "sti subtype parent base mismatch: #{subtype.entity_id}"
      end
      return if parent_entity[:table_name] == subtype.table_name

      raise ArgumentError, "sti subtype parent table mismatch: #{subtype.entity_id}"
    end

    def resolve_parent_entity(subtype, physical_entities, subtypes_by_id)
      if physical_entities.key?(subtype.parent_entity_id)
        entity = physical_entities.fetch(subtype.parent_entity_id)
        unless subtype.parent_entity_id == subtype.base_entity_id
          raise ArgumentError, "sti subtype parent must reference base entity: #{subtype.entity_id}"
        end

        return {
          entity_id: subtype.parent_entity_id,
          base_entity_id: subtype.parent_entity_id,
          table_name: entity.table_name
        }
      end

      parent_subtype = subtypes_by_id.fetch(subtype.parent_entity_id) do
        raise ArgumentError, "sti subtype parent missing: #{subtype.entity_id}"
      end
      {
        entity_id: parent_subtype.entity_id,
        base_entity_id: parent_subtype.base_entity_id,
        table_name: parent_subtype.table_name
      }
    end

    def validate_relationship_endpoints!(relationship_domain, physical_entity_ids)
      invalid_endpoint_ids = relationship_domain.relationships.flat_map do |relationship|
        [relationship.owner_entity_id, relationship.target_entity_id]
      end
      invalid_endpoint = invalid_endpoint_ids.find { |entity_id| !physical_entity_ids.include?(entity_id) }
      return unless invalid_endpoint

      raise ArgumentError, "relationship endpoint must be physical: #{invalid_endpoint}"
    end

    def base_metadata_by_entity_id(subtype_entities)
      subtype_entities.group_by(&:base_entity_id).transform_values do |group|
        inheritance_columns = group.map(&:inheritance_column).uniq
        if inheritance_columns.length != 1
          raise ArgumentError, "sti base inheritance_column mismatch: #{group.first.base_entity_id}"
        end

        {
          'kind' => 'sti_base',
          'inheritance_column' => inheritance_columns.first
        }
      end
    end

    def ensure_unique_ids!(ids, label)
      duplicate_id = ids.group_by(&:itself).find { |_id, group| group.length > 1 }&.first
      return unless duplicate_id

      raise ArgumentError, "duplicate #{label}: #{duplicate_id}"
    end
  end
  # rubocop:enable Metrics/AbcSize, Metrics/ClassLength, Metrics/MethodLength
end
