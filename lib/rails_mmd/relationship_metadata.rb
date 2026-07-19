# frozen_string_literal: true

require 'rails_mmd/canonical_json'

module RailsMmd
  # Normalizes and merges advisory metadata carried by public relationships.
  # rubocop:disable Metrics/AbcSize, Metrics/CyclomaticComplexity, Metrics/MethodLength, Metrics/ModuleLength, Metrics/ParameterLists, Metrics/PerceivedComplexity
  module RelationshipMetadata
    module_function

    DEPENDENT_ACTIONS = {
      belongs_to: %i[destroy delete destroy_async],
      has_one: %i[destroy destroy_async delete nullify restrict_with_error restrict_with_exception],
      has_many: %i[destroy destroy_async delete_all nullify restrict_with_error restrict_with_exception]
    }.freeze
    STRUCTURED_COLUMN_PATTERN = /\A[a-z][a-z0-9]*(?:_[a-z0-9]+)*\z/

    def for_declaration(reflection:, association_name:, association_macro:, through:, direction:, scoped:)
      options = safe_value(reflection, :options)
      declaration = behavior_declaration(
        reflection, options, association_name: association_name,
                             association_macro: association_macro, through: through
      )
      metadata = {}
      metadata[:scoped] = true if scoped
      metadata[:behavior] = { direction => [declaration] } if declaration
      deep_freeze(metadata.empty? ? nil : metadata)
    end

    def scoped(value)
      deep_freeze(value ? { scoped: true } : nil)
    end

    def merge(*metadata_values)
      values = metadata_values.compact
      metadata = {}
      metadata[:scoped] = true if values.any? { |value| value[:scoped] == true }
      behavior = %i[from_owner from_target].to_h do |direction|
        records = values.flat_map { |value| Array(value.dig(:behavior, direction)) }
        normalized = canonical_records(records)
        [direction, normalized.empty? ? nil : normalized]
      end.compact
      metadata[:behavior] = behavior unless behavior.empty?
      deep_freeze(metadata.empty? ? nil : metadata)
    end

    def public_payload(metadata)
      return unless metadata

      payload = {}
      payload['scoped'] = true if metadata[:scoped] == true
      behavior = public_behavior(metadata[:behavior])
      payload['behavior'] = behavior if behavior
      payload.empty? ? nil : payload
    end

    def canonical_records(records)
      records.to_h { |record| [CanonicalJson.dump(record), record] }.sort.map(&:last)
    end
    private_class_method :canonical_records

    def public_behavior(behavior)
      return unless behavior.is_a?(Hash)

      payload = %i[from_owner from_target].to_h do |direction|
        records = Array(behavior[direction]).map { |record| public_declaration(record) }
        [direction.to_s, records.empty? ? nil : records]
      end.compact
      payload unless payload.empty?
    end
    private_class_method :public_behavior

    def public_declaration(record)
      payload = {
        'association_name' => record.fetch(:association_name),
        'association_macro' => record.fetch(:association_macro)
      }
      payload['dependent'] = stringify_keys(record[:dependent]) if record[:dependent]
      payload['touch'] = stringify_keys(record[:touch]) if record[:touch]
      payload['counter_cache'] = stringify_keys(record[:counter_cache]) if record[:counter_cache]
      payload
    end
    private_class_method :public_declaration

    def stringify_keys(value)
      value.to_h { |key, item| [key.to_s, item] }
    end
    private_class_method :stringify_keys

    def behavior_declaration(reflection, options, association_name:, association_macro:, through:)
      dependent = dependent_payload(options, association_macro, through)
      touch = touch_payload(options, association_macro)
      counter_cache = counter_cache_payload(reflection, options, association_macro)
      return unless dependent || touch || counter_cache

      declaration = {
        association_name: association_name,
        association_macro: association_macro.to_s
      }
      declaration[:dependent] = dependent if dependent
      declaration[:touch] = touch if touch
      declaration[:counter_cache] = counter_cache if counter_cache
      declaration
    end
    private_class_method :behavior_declaration

    def dependent_payload(options, macro, through)
      return unless options.is_a?(Hash)

      action = options[:dependent]
      return unless action.is_a?(String) || action.is_a?(Symbol)

      action = DEPENDENT_ACTIONS.fetch(macro, []).find { |allowed| allowed.to_s == action.to_s }
      return unless action
      return if macro == :has_one && through

      target = macro == :has_many && through ? 'through_records' : 'associated_records'
      { action: action.to_s, target: target }
    end
    private_class_method :dependent_payload

    def touch_payload(options, macro)
      return unless options.is_a?(Hash) && %i[belongs_to has_one].include?(macro)

      touch = options[:touch]
      return { attribute: nil } if touch == true
      return unless touch.is_a?(String) || touch.is_a?(Symbol)

      attribute = touch.to_s
      { attribute: attribute } if attribute.match?(STRUCTURED_COLUMN_PATTERN)
    end
    private_class_method :touch_payload

    def counter_cache_payload(reflection, options, macro)
      return unless options.is_a?(Hash) && macro == :belongs_to

      counter_cache = options[:counter_cache]
      return unless counter_cache.is_a?(Hash)

      active = counter_cache[:active]
      return unless [true, false].include?(active)

      column = safe_value(reflection, :counter_cache_column)
      return unless column.is_a?(String) && column.match?(STRUCTURED_COLUMN_PATTERN)

      { column: column, active: active }
    end
    private_class_method :counter_cache_payload

    def safe_value(object, method_name)
      return unless object.respond_to?(method_name)

      object.public_send(method_name)
    rescue LoadError, SyntaxError, StandardError
      nil
    end
    private_class_method :safe_value

    def deep_freeze(value)
      case value
      when Hash
        value.each do |key, item|
          deep_freeze(key)
          deep_freeze(item)
        end
      when Array
        value.each { |item| deep_freeze(item) }
      end
      value&.freeze
    end
    private_class_method :deep_freeze
  end
  # rubocop:enable Metrics/AbcSize, Metrics/CyclomaticComplexity, Metrics/MethodLength, Metrics/ModuleLength, Metrics/ParameterLists, Metrics/PerceivedComplexity
end
