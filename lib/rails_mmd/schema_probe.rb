# frozen_string_literal: true

require 'rails_mmd/diagnostics'
require 'rails_mmd/redactor'

module RailsMmd
  # Reads selected-domain-only schema metadata for resolved renderable records.
  # rubocop:disable Metrics/ClassLength, Metrics/MethodLength
  class SchemaProbe
    DomainResult = Struct.new(:domain_id, :entities, :join_tables, :diagnostics, keyword_init: true)
    Entity = Struct.new(
      :ruby_constant,
      :table_name,
      :connection_context_id,
      :columns,
      :primary_key,
      :foreign_keys,
      :indexes,
      keyword_init: true
    )
    Column = Struct.new(:name, :type, :nullable, keyword_init: true)
    JoinTable = Struct.new(:table_name, :columns, :primary_key, keyword_init: true)
    ForeignKey = Struct.new(:from_table, :column, :to_table, :primary_key, keyword_init: true)
    Index = Struct.new(:columns, :unique, :where, :using, :expression, keyword_init: true)
    # Carries valid metadata records when only some optional adapter rows degrade.
    class PartialMetadataDegraded < StandardError
      attr_reader :records

      def initialize(records:, message:)
        @records = records
        super(message)
      end
    end
    Result = Struct.new(:domains, :diagnostics, keyword_init: true)

    def initialize(model_resolver:, diagnostics: Diagnostics.new, redactor: Redactor.new)
      @model_resolver = model_resolver
      @diagnostics = diagnostics
      @redactor = redactor
    end

    def probe(domains:)
      domain_results = domains.map { |domain| probe_domain(domain) }
      all_diagnostics = domain_results.flat_map(&:diagnostics)

      Result.new(domains: domain_results, diagnostics: all_diagnostics)
    end

    private

    attr_reader :diagnostics, :model_resolver, :redactor

    def probe_domain(domain)
      connection_diagnostic = multi_db_diagnostic(domain)
      return domain_result(domain, [], [connection_diagnostic]) if connection_diagnostic

      entities = []
      entity_models = []
      output_diagnostics = []
      domain.records.each do |record|
        model = model_for(record)
        entity, record_diagnostics = probe_record(domain.domain_id, record, model)
        if entity
          entities << entity
          entity_models << model
        end
        output_diagnostics.concat(record_diagnostics)
      end

      domain_result(domain, entities, output_diagnostics, probe_join_tables(entity_models))
    end

    def domain_result(domain, entities, output_diagnostics, join_tables = [])
      DomainResult.new(
        domain_id: domain.domain_id, entities: entities,
        join_tables: join_tables, diagnostics: output_diagnostics
      )
    end

    def multi_db_diagnostic(domain)
      raw_context_ids = domain.records.map(&:connection_context_id)
      return if raw_context_ids.uniq.length < 2

      connection_context_ids = raw_context_ids.map { |context_id| redactor.sanitize(context_id) }.sort

      diagnostics.build(
        code: 'MULTI_DB_UNSUPPORTED',
        message: "Domain #{domain.domain_id} selects multiple connection contexts",
        subject_id: domain.domain_id,
        metadata: { domain_id: domain.domain_id, connection_context_ids: connection_context_ids }
      )
    end

    def probe_record(domain_id, record, model)
      return invalid_record(domain_id, record, :table) if model.nil?

      return invalid_record(domain_id, record, :table) unless table_exists?(model)

      columns = read_columns(model)
      primary_key = read_primary_key(model)
      return invalid_record(domain_id, record, :table) if columns.nil?
      return invalid_record(domain_id, record, :primary_key) unless scalar_primary_key?(primary_key)

      build_entity(domain_id, record, model, columns, primary_key)
    end

    def model_for(record)
      model_resolver.call(record.ruby_constant)
    rescue LoadError, SyntaxError, StandardError
      nil
    end

    def invalid_record(domain_id, record, kind)
      diagnostic = if kind == :primary_key
                     primary_key_unsupported(domain_id, record)
                   else
                     table_missing(domain_id, record, 'table metadata unavailable')
                   end
      [nil, [diagnostic]]
    end

    def build_entity(domain_id, record, model, columns, primary_key)
      foreign_keys, foreign_key_diagnostic = degradable_metadata(domain_id, record, 'foreign_key') do
        read_foreign_keys(model, record.table_name)
      end
      indexes, index_diagnostic = degradable_metadata(domain_id, record, 'unique_index') do
        read_indexes(model, record.table_name)
      end

      [
        Entity.new(
          ruby_constant: record.ruby_constant,
          table_name: record.table_name,
          connection_context_id: record.connection_context_id,
          columns: columns,
          primary_key: primary_key,
          foreign_keys: foreign_keys,
          indexes: indexes
        ),
        [foreign_key_diagnostic, index_diagnostic].compact
      ]
    end

    def table_exists?(model)
      return true unless model.respond_to?(:table_exists?)

      model.table_exists?
    rescue LoadError, SyntaxError, StandardError
      false
    end

    def read_columns(model)
      return [] unless model.respond_to?(:columns)

      model.columns.map { |column| column_record(column) }
    rescue LoadError, SyntaxError, StandardError
      nil
    end

    def probe_join_tables(models)
      join_table_requests(models).group_by(&:last).filter_map do |table_name, requests|
        requests.lazy.filter_map { |model, _name| read_join_table(model, table_name) }.first
      end.sort_by(&:table_name)
    end

    def join_table_requests(models)
      models.flat_map do |model|
        habtm_reflections(model).filter_map do |reflection|
          table_name = safe_value_from(reflection, :join_table)
          [model, table_name] if table_name.is_a?(String) && !table_name.empty?
        end
      end
    end

    def join_table_connection(model, table_name)
      return unless model.respond_to?(:connection)

      connection = model.connection
      return unless connection.respond_to?(:data_source_exists?) && connection.data_source_exists?(table_name)
      return unless connection.respond_to?(:columns) && connection.respond_to?(:primary_key)

      connection
    rescue LoadError, SyntaxError, StandardError
      nil
    end

    def habtm_reflections(model)
      return [] unless model.respond_to?(:reflect_on_all_associations)

      Array(model.reflect_on_all_associations(:has_and_belongs_to_many))
    rescue LoadError, SyntaxError, StandardError
      []
    end

    def read_join_table(model, table_name)
      connection = join_table_connection(model, table_name)
      return unless connection

      JoinTable.new(
        table_name: table_name,
        columns: Array(connection.columns(table_name)).map { |column| column_record(column) },
        primary_key: connection.primary_key(table_name)
      )
    rescue LoadError, SyntaxError, StandardError
      nil
    end

    def column_record(column)
      Column.new(
        name: value_from(column, :name),
        type: value_from(column, :type),
        nullable: value_from(column, :null)
      )
    end

    def safe_value_from(object, method_name)
      value_from(object, method_name)
    rescue LoadError, SyntaxError, StandardError
      nil
    end

    def read_primary_key(model)
      model.respond_to?(:primary_key) ? model.primary_key : nil
    rescue LoadError, SyntaxError, StandardError
      nil
    end

    def scalar_primary_key?(primary_key)
      primary_key.is_a?(String) && !primary_key.empty?
    end

    def degradable_metadata(domain_id, record, metadata_kind)
      [yield, nil]
    rescue PartialMetadataDegraded => e
      [e.records, metadata_degraded(domain_id, record, metadata_kind, e.message)]
    rescue LoadError, NotImplementedError, SyntaxError, StandardError => e
      [[], metadata_degraded(domain_id, record, metadata_kind, e.message)]
    end

    def read_foreign_keys(model, table_name)
      foreign_keys = if model.respond_to?(:foreign_keys)
                       model.foreign_keys
                     else
                       connection_metadata(model, :foreign_keys, table_name)
                     end
      valid_records = valid_metadata_records(Array(foreign_keys)) { |foreign_key| foreign_key_record(foreign_key) }
      return valid_records if valid_records.length == Array(foreign_keys).length

      raise PartialMetadataDegraded.new(records: valid_records, message: 'foreign_key metadata inconsistent')
    end

    def read_indexes(model, table_name)
      indexes = if model.respond_to?(:indexes)
                  model.indexes
                else
                  connection_metadata(model, :indexes, table_name)
                end
      column_names = model.columns.map { |column| value_from(column, :name) }
      valid_records = valid_metadata_records(Array(indexes)) { |index| index_record(index, column_names) }
      return valid_records if valid_records.length == Array(indexes).length

      raise PartialMetadataDegraded.new(records: valid_records, message: 'unique_index metadata inconsistent')
    end

    def valid_metadata_records(records)
      records.filter_map do |record|
        yield record
      rescue ArgumentError
        nil
      end
    end

    def foreign_key_record(foreign_key)
      record = ForeignKey.new(
        from_table: value_from(foreign_key, :from_table),
        column: value_from(foreign_key, :column),
        to_table: value_from(foreign_key, :to_table),
        primary_key: value_from(foreign_key, :primary_key)
      )
      return record if [record.from_table, record.column, record.to_table, record.primary_key].all? do |value|
        value.is_a?(String) && !value.empty?
      end

      raise ArgumentError, 'foreign_key metadata inconsistent'
    end

    def index_record(index, column_names)
      record = Index.new(
        columns: value_from(index, :columns),
        unique: value_from(index, :unique),
        where: value_from(index, :where),
        using: normalized_index_using(value_from(index, :using)),
        expression: value_from(index, :expression)
      )
      return record if index_record_valid?(record, column_names)

      raise ArgumentError, 'unique_index metadata inconsistent'
    end

    def index_record_valid?(record, column_names)
      index_columns_valid?(record.columns, column_names) &&
        boolean?(record.unique) &&
        optional_index_fields_valid?(record)
    end

    def index_columns_valid?(columns, column_names)
      columns.is_a?(Array) &&
        columns.all? { |column| column.is_a?(String) && !column.empty? } &&
        columns.all? { |column| column_names.include?(column) }
    end

    def boolean?(value)
      [true, false].include?(value)
    end

    def optional_index_fields_valid?(record)
      optional_string_or_nil?(record.where) &&
        optional_string_or_nil?(record.expression) &&
        optional_string_or_nil?(record.using)
    end

    def optional_string_or_nil?(value)
      value.nil? || value.is_a?(String)
    end

    def normalized_index_using(value)
      return value.to_s if value.is_a?(Symbol)

      value
    end

    def connection_metadata(model, method_name, table_name)
      raise "#{method_name} metadata unavailable" unless model.respond_to?(:connection)
      raise "#{method_name} metadata unavailable" unless model.connection.respond_to?(method_name)

      model.connection.public_send(method_name, table_name)
    end

    def value_from(object, method_name)
      return unless object.respond_to?(method_name)

      object.public_send(method_name)
    end

    def table_missing(domain_id, record, reason)
      diagnostics.build(
        code: 'MODEL_TABLE_MISSING',
        message: "#{record.ruby_constant} table metadata is unavailable: #{reason}",
        subject_id: "#{domain_id}:#{record.ruby_constant}",
        metadata: { domain_id: domain_id, ruby_constant: record.ruby_constant, table_name: record.table_name }
      )
    end

    def primary_key_unsupported(domain_id, record)
      diagnostics.build(
        code: 'MODEL_PRIMARY_KEY_UNSUPPORTED',
        message: "#{record.ruby_constant} primary key is unsupported",
        subject_id: "#{domain_id}:#{record.ruby_constant}",
        metadata: { domain_id: domain_id, ruby_constant: record.ruby_constant, table_name: record.table_name }
      )
    end

    def metadata_degraded(domain_id, record, metadata_kind, reason)
      diagnostics.build(
        code: 'DB_METADATA_DEGRADED',
        message: "#{record.ruby_constant} #{metadata_kind} metadata is degraded",
        subject_id: domain_id,
        metadata: {
          domain_id: domain_id,
          ruby_constant: record.ruby_constant,
          metadata_kind: metadata_kind,
          reason: reason
        }
      )
    end
  end
  # rubocop:enable Metrics/ClassLength, Metrics/MethodLength
end
