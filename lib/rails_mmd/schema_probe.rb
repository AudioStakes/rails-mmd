# frozen_string_literal: true

require 'rails_mmd/diagnostics'
require 'rails_mmd/redactor'

module RailsMmd
  # Reads selected-domain-only schema metadata for resolved renderable records.
  # rubocop:disable Metrics/ClassLength, Metrics/MethodLength
  class SchemaProbe
    DomainResult = Struct.new(:domain_id, :entities, :diagnostics, keyword_init: true)
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
    ForeignKey = Struct.new(:from_table, :column, :to_table, :primary_key, keyword_init: true)
    Index = Struct.new(:columns, :unique, keyword_init: true)
    Result = Struct.new(:domains, :diagnostics, :exit_code, keyword_init: true) do
      def success?
        diagnostics.none? { |diagnostic| diagnostic.fetch('severity') != 'warning' }
      end
    end

    EXIT_CONTRACT_ERROR = 2

    def initialize(model_resolver:, diagnostics: Diagnostics.new, redactor: Redactor.new)
      @model_resolver = model_resolver
      @diagnostics = diagnostics
      @redactor = redactor
    end

    def probe(domains:)
      domain_results = domains.map { |domain| probe_domain(domain) }
      all_diagnostics = domain_results.flat_map(&:diagnostics)

      Result.new(domains: domain_results, diagnostics: all_diagnostics, exit_code: exit_code(all_diagnostics))
    end

    private

    attr_reader :diagnostics, :model_resolver, :redactor

    def probe_domain(domain)
      connection_diagnostic = multi_db_diagnostic(domain)
      return domain_result(domain, [], [connection_diagnostic]) if connection_diagnostic

      entities = []
      output_diagnostics = []
      domain.records.each do |record|
        entity, record_diagnostics = probe_record(domain.domain_id, record)
        entities << entity if entity
        output_diagnostics.concat(record_diagnostics)
      end

      domain_result(domain, entities, output_diagnostics)
    end

    def domain_result(domain, entities, output_diagnostics)
      DomainResult.new(domain_id: domain.domain_id, entities: entities, diagnostics: output_diagnostics)
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

    def probe_record(domain_id, record)
      model = model_for(record)
      return invalid_record(domain_id, record, :table) if model.nil?

      return invalid_record(domain_id, record, :table) unless table_exists?(model)

      columns = read_columns(model)
      primary_key = read_primary_key(model)
      return invalid_record(domain_id, record, :table) if columns.nil?
      return invalid_record(domain_id, record, :primary_key) unless scalar_primary_key?(primary_key)

      build_entity(domain_id, record, model, columns, primary_key)
    end

    def exit_code(all_diagnostics)
      all_diagnostics.any? { |diagnostic| diagnostic.fetch('severity') != 'warning' } ? EXIT_CONTRACT_ERROR : 0
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

      model.columns.map do |column|
        Column.new(
          name: value_from(column, :name),
          type: value_from(column, :type),
          nullable: value_from(column, :null)
        )
      end
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
    rescue LoadError, SyntaxError, StandardError => e
      [[], metadata_degraded(domain_id, record, metadata_kind, e.message)]
    end

    def read_foreign_keys(model, table_name)
      foreign_keys = if model.respond_to?(:foreign_keys)
                       model.foreign_keys
                     else
                       connection_metadata(model, :foreign_keys, table_name)
                     end
      Array(foreign_keys).map do |foreign_key|
        ForeignKey.new(
          from_table: value_from(foreign_key, :from_table),
          column: value_from(foreign_key, :column),
          to_table: value_from(foreign_key, :to_table),
          primary_key: value_from(foreign_key, :primary_key)
        )
      end
    end

    def read_indexes(model, table_name)
      indexes = if model.respond_to?(:indexes)
                  model.indexes
                else
                  connection_metadata(model, :indexes, table_name)
                end
      Array(indexes).map do |index|
        Index.new(columns: value_from(index, :columns), unique: value_from(index, :unique))
      end
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
