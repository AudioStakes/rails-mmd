# frozen_string_literal: true

require 'rails_mmd/canonical_json'
require 'rails_mmd/redactor'

module RailsMmd
  # Builds schema-free ActiveRecord model inventory records.
  # rubocop:disable Metrics/ClassLength, Metrics/MethodLength
  class ModelInventory
    Record = Struct.new(
      :ruby_constant,
      :abstract_class,
      :base_class,
      :table_name,
      :connection_context_id,
      :renderable,
      :renderability_reason,
      keyword_init: true
    )
    CONNECTION_CONTEXT_KEYS = %w[name role shard adapter database host port username].freeze

    def initialize(active_record_base:, constant_resolver: method(:default_constant_resolver),
                   redactor: Redactor.new)
      @active_record_base = active_record_base
      @constant_resolver = constant_resolver
      @redactor = redactor
    end

    def records
      active_record_base.descendants.filter_map do |model|
        next unless inventoriable?(model)

        build_record(model)
      end
    end

    private

    attr_reader :active_record_base, :constant_resolver, :redactor

    def inventoriable?(model)
      name = model.name
      return false unless name.is_a?(String) && !name.empty?

      constant_resolver.call(name).equal?(model)
    rescue Exception => e # rubocop:disable Lint/RescueException
      raise if e.is_a?(Interrupt) || e.is_a?(SystemExit)

      false
    end

    def build_record(model)
      table_name, table_error = table_name_for(model)
      abstract = abstract_class?(model)
      base_model = base_class(model)
      renderability_reason = renderability_reason(model, abstract, base_model, table_error)

      Record.new(
        ruby_constant: model.name,
        abstract_class: abstract,
        base_class: base_model&.name,
        table_name: table_name,
        connection_context_id: connection_context_id(model),
        renderable: renderability_reason.nil?,
        renderability_reason: renderability_reason
      )
    end

    def abstract_class?(model)
      model.respond_to?(:abstract_class?) && model.abstract_class?
    end

    def base_class(model)
      model.respond_to?(:base_class) ? model.base_class : model
    end

    def table_name_for(model)
      [model.table_name, nil]
    rescue StandardError => e
      [nil, e]
    end

    def renderability_reason(model, abstract, base_model, table_error)
      return 'abstract_class' if abstract
      return 'sti_subclass' unless base_model.equal?(model)
      return "table_name_unavailable: #{redactor.sanitize(table_error.message)}" if table_error

      nil
    end

    def connection_context_id(model)
      CanonicalJson.dump(connection_context(model))
    end

    def connection_context(model)
      if model.respond_to?(:connection_context)
        sanitize_context(model.connection_context)
      elsif model.respond_to?(:connection_db_config)
        context_from_db_config(model)
      else
        { 'model' => model.name }
      end
    end

    def context_from_db_config(model)
      db_config = model.connection_db_config
      {
        'name' => value_from(db_config, :name),
        'role' => value_from(model, :current_role) || 'default',
        'shard' => value_from(model, :current_shard) || 'default',
        'adapter' => value_from(db_config, :adapter),
        'database' => value_from(db_config, :database),
        'host' => value_from(db_config, :host),
        'port' => value_from(db_config, :port),
        'username' => value_from(db_config, :username)
      }
    end

    def sanitize_context(context)
      raw_context = context.to_h.transform_keys(&:to_s)
      CONNECTION_CONTEXT_KEYS.to_h do |key|
        [key, sanitize_context_value(raw_context.fetch(key, default_context_value(key)))]
      end
    end

    def sanitize_context_value(value)
      value.is_a?(String) ? redactor.sanitize(value) : value
    end

    def default_context_value(key)
      %w[role shard].include?(key) ? 'default' : nil
    end

    def value_from(object, method_name)
      return unless object.respond_to?(method_name)

      value = object.public_send(method_name)
      sanitize_context_value(value)
    end

    def default_constant_resolver(name)
      name.split('::').reduce(Object) { |namespace, const_name| namespace.const_get(const_name, false) }
    end
  end
  # rubocop:enable Metrics/ClassLength, Metrics/MethodLength
end
