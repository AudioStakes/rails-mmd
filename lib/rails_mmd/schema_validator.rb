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
      schema(schema_name).valid?(payload)
    end

    def errors(schema_name, payload)
      schema(schema_name).validate(payload).to_a
    end

    private

    attr_reader :schema_root, :schemas

    def schema(schema_name)
      key = schema_name.to_sym
      schemas[key] ||= JSONSchemer.schema(JSON.parse(schema_root.join(SCHEMA_FILES.fetch(key)).read))
    end
  end
end
