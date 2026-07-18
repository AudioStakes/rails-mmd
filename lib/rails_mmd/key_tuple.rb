# frozen_string_literal: true

require_relative 'canonical_json'

module RailsMmd
  # Normalizes ordered physical key columns at metadata boundaries.
  module KeyTuple
    module_function

    def normalize(value)
      values = value.is_a?(Array) ? value : [value]
      return unless valid_members?(values)

      values.map { |member| member.dup.freeze }.freeze
    end

    def valid_pair?(foreign_columns, referenced_columns)
      foreign_tuple = normalize(foreign_columns)
      referenced_tuple = normalize(referenced_columns)

      !foreign_tuple.nil? && !referenced_tuple.nil? && foreign_tuple.length == referenced_tuple.length
    end

    def identity(payload)
      CanonicalJson.dump(payload)
    end

    def valid_members?(values)
      all_strings = values.all? { |member| member.is_a?(String) && !member.empty? }
      !values.empty? && all_strings && values.uniq.length == values.length
    end
    private_class_method :valid_members?
  end
end
