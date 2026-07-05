# frozen_string_literal: true

require 'json'

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

    def definitions
      @definitions ||= JSON.parse(schema_path.read).fetch('$defs')
    end
  end
end
