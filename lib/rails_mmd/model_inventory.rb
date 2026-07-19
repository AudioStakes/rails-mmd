# frozen_string_literal: true

require 'rails_mmd/canonical_json'
require 'rails_mmd/constant_resolver'
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

    def initialize(active_record_base:, constant_resolver: ConstantResolver.new,
                   redactor: Redactor.new)
      @active_record_base = active_record_base
      @constant_resolver = ConstantResolver.wrap(constant_resolver)
      @redactor = redactor
    end

    def records
      active_record_base.descendants.filter_map do |model|
        next unless constant_backed_model?(model)

        build_record(model)
      end
    end

    private

    attr_reader :active_record_base, :constant_resolver, :redactor

    def constant_backed_model?(model)
      model_name = model.name
      return false unless model_name.is_a?(String) && !model_name.empty?

      constant_resolver.resolve(model_name).equal?(model)
    end

    def build_record(model)
      table_name, table_error = table_name_for(model)
      connection_context_id, connection_context_error = connection_context_id_for(model)
      abstract = abstract_class?(model)
      base_model = base_class(model)
      renderability_reason = renderability_reason(model, abstract, base_model, table_error, connection_context_error)

      Record.new(
        ruby_constant: model.name,
        abstract_class: abstract,
        base_class: base_model&.name,
        table_name: table_name,
        connection_context_id: connection_context_id,
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

    def renderability_reason(model, abstract, base_model, table_error, connection_context_error)
      return 'abstract_class' if abstract
      return 'sti_subclass' unless base_model.equal?(model)
      return "table_name_unavailable: #{redactor.sanitize(table_error.message)}" if table_error
      if connection_context_error
        return "connection_context_unavailable: #{redactor.sanitize(connection_context_error.message)}"
      end

      nil
    end

    def connection_context_id_for(model)
      [CanonicalJson.dump(connection_context(model)), nil]
    rescue StandardError => e
      [CanonicalJson.dump('model' => model.name), e]
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
        'name' => connection_context_value(db_config, :name),
        'role' => connection_context_value(model, :current_role) || 'default',
        'shard' => connection_context_value(model, :current_shard) || 'default',
        'adapter' => connection_context_value(db_config, :adapter),
        'database' => connection_context_value(db_config, :database),
        'host' => connection_context_value(db_config, :host),
        'port' => connection_context_value(db_config, :port),
        'username' => connection_context_value(db_config, :username)
      }
    end

    def sanitize_context(context)
      raw_context = context.to_h.transform_keys(&:to_s)
      CONNECTION_CONTEXT_KEYS.to_h do |key|
        [key, sanitize_context_value(raw_context.fetch(key, default_context_value(key)))]
      end
    end

    def sanitize_context_value(value)
      value
    end

    def default_context_value(key)
      %w[role shard].include?(key) ? 'default' : nil
    end

    def connection_context_value(connection_source, method_name)
      return unless connection_source.respond_to?(method_name)

      context_value = connection_source.public_send(method_name)
      sanitize_context_value(context_value)
    end
  end
  # rubocop:enable Metrics/ClassLength, Metrics/MethodLength
end
