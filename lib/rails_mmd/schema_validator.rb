# frozen_string_literal: true

require 'json'
require 'json_schemer'

module RailsMmd
  # Validates payloads against repository JSON Schemas.
  class SchemaValidator
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
      errors(schema_name, payload).empty?
    end

    def errors(schema_name, payload)
      schema(schema_name).validate(payload).to_a + attribute_identity_errors(schema_name, payload)
    end

    private

    attr_reader :schema_root, :schemas

    def schema(schema_name)
      key = schema_name.to_sym
      schemas[key] ||= JSONSchemer.schema(JSON.parse(schema_root.join(SCHEMA_FILES.fetch(key)).read))
    end

    def attribute_identity_errors(schema_name, payload)
      return [] unless %i[ir render_plan].include?(schema_name.to_sym)
      return [] unless payload.is_a?(Hash) && payload['entities'].is_a?(Array)

      seen = {}
      payload['entities'].each_with_index.flat_map do |entity, entity_index|
        duplicate_attribute_errors(entity, entity_index, seen)
      end
    end

    def duplicate_attribute_errors(entity, entity_index, seen)
      return [] unless entity.is_a?(Hash) && entity['attributes'].is_a?(Array)

      entity['attributes'].each_with_index.filter_map do |attribute, attribute_index|
        duplicate_attribute_error(attribute, entity_index, attribute_index, seen)
      end
    end

    def duplicate_attribute_error(attribute, entity_index, attribute_index, seen)
      return unless attribute.is_a?(Hash) && attribute['attribute_id'].is_a?(String)

      attribute_id = attribute['attribute_id']
      return remember_attribute_index(seen, attribute_id, attribute_index) unless seen.key?(attribute_id)

      duplicate_attribute_error_payload(entity_index, attribute_index, attribute_id, seen.fetch(attribute_id))
    end

    def remember_attribute_index(seen, attribute_id, attribute_index)
      seen[attribute_id] = attribute_index
      nil
    end

    def duplicate_attribute_error_payload(entity_index, attribute_index, attribute_id, first_index)
      {
        'data_pointer' => "/entities/#{entity_index}/attributes/#{attribute_index}/attribute_id",
        'schema_pointer' => '/x-unique-attribute-identities',
        'type' => 'unique_attribute_identity',
        'details' => { 'attribute_id' => attribute_id, 'first_index' => first_index }
      }
    end
  end
end
