# frozen_string_literal: true

require 'json'
require 'json_schemer'

module RailsMmd
  # Reads diagnostic metadata contracts from the diagnostics JSON Schema.
  class MetadataShapes
    def initialize(schema_path:)
      @schema_path = schema_path
    end

    def fetch(code)
      shapes.fetch(code)
    end

    def properties
      @properties ||= shapes.values.each_with_object({}) do |shape, output|
        output.merge!(shape.fetch('properties'))
      end
    end

    def validate!(code, metadata)
      errors = schema(code).validate(metadata).to_a
      return if errors.empty?

      raise ArgumentError, "invalid diagnostic metadata for #{code}: #{errors.first.fetch('data_pointer')}"
    end

    private

    attr_reader :schema_path

    def shapes
      @shapes ||= metadata_rules.to_h do |rule|
        code = rule.dig('if', 'properties', 'code', 'const')
        ref = rule.dig('then', 'properties', 'metadata', '$ref')
        [code, definitions.fetch(ref.split('/').last)]
      end
    end

    def metadata_rules
      definitions.values.select { |definition| definition.dig('then', 'properties', 'metadata', '$ref') }
    end

    def schema(code)
      @schemas ||= {}
      @schemas[code] ||= JSONSchemer.schema(fetch(code).merge('$defs' => definitions))
    end

    def definitions
      @definitions ||= JSON.parse(schema_path.read).fetch('$defs')
    end
  end
end
