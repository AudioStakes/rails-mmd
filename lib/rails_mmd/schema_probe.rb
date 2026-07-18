# frozen_string_literal: true

require 'rails_mmd/diagnostics'
require 'rails_mmd/association_binding_resolver'
require 'rails_mmd/key_tuple'
require 'rails_mmd/redactor'

module RailsMmd
  # Reads selected-domain-only schema metadata for resolved renderable records.
  # rubocop:disable Metrics/AbcSize, Metrics/ClassLength, Metrics/CyclomaticComplexity
  # rubocop:disable Metrics/MethodLength, Metrics/ParameterLists, Metrics/PerceivedComplexity
  class SchemaProbe
    DomainResult = Struct.new(
      :domain_id,
      :entities,
      :sti_subtypes,
      :join_tables,
      :delegated_type_families,
      :diagnostics,
      keyword_init: true
    )
    Entity = Struct.new(
      :ruby_constant,
      :table_name,
      :connection_context_id,
      :columns,
      :primary_key_columns,
      :foreign_keys,
      :indexes,
      :selection_origin,
      keyword_init: true
    )
    StiSubtype = Struct.new(
      :entity_id,
      :base_entity_id,
      :parent_entity_id,
      :ruby_constant,
      :table_name,
      :inheritance_column,
      :sti_name,
      :depth,
      keyword_init: true
    )
    DelegatedTypeFamily = Struct.new(
      :owner_entity_id,
      :owner_ruby_constant,
      :association_name,
      :foreign_key_columns,
      :foreign_type,
      :scoped,
      :root_diagnostic_code,
      :targets,
      keyword_init: true
    )
    DelegatedTypeTarget = Struct.new(
      :ruby_constant,
      :entity_id,
      :status,
      :diagnostic_code,
      keyword_init: true
    )
    Column = Struct.new(:name, :type, :nullable, keyword_init: true)
    JoinTable = Struct.new(
      :table_name,
      :connection_context_id,
      :columns,
      :primary_key_columns,
      keyword_init: true
    )
    ForeignKey = Struct.new(:from_table, :columns, :to_table, :primary_key_columns, keyword_init: true)
    Index = Struct.new(:columns, :unique, :where, :using, :expression, keyword_init: true)
    # Carries valid metadata records when only some optional adapter rows degrade.
    class PartialMetadataDegraded < StandardError
      attr_reader :records

      def initialize(records:, message:)
        @records = records
        super(message)
      end
    end
    Result = Struct.new(:domains, :diagnostics, :exit_code, keyword_init: true) do
      def success?
        diagnostics.none? { |diagnostic| diagnostic.fetch('severity') != 'warning' }
      end
    end

    EXIT_CONTRACT_ERROR = 2
    ASSOCIATION_NAME_PATTERN = /\A[a-z][a-z0-9]*(?:_[a-z0-9]+)*[!?=]?\z/

    def initialize(model_resolver:, diagnostics: Diagnostics.new, redactor: Redactor.new)
      @model_resolver = model_resolver
      @diagnostics = diagnostics
      @redactor = redactor
    end

    def probe(domains:, inventory_records: [], owned_domain_ids_by_constant: {})
      records_by_constant = inventory_records.to_h { |record| [record.ruby_constant, record] }
      domain_results = domains.map do |domain|
        probe_domain(domain, inventory_records, records_by_constant, owned_domain_ids_by_constant)
      end
      all_diagnostics = domain_results.flat_map(&:diagnostics)

      Result.new(domains: domain_results, diagnostics: all_diagnostics, exit_code: exit_code(all_diagnostics))
    end

    private

    attr_reader :diagnostics, :model_resolver, :redactor

    def probe_domain(domain, inventory_records, records_by_constant, owned_domain_ids_by_constant)
      connection_diagnostic = multi_db_diagnostic(domain)
      return domain_result(domain, [], [connection_diagnostic]) if connection_diagnostic

      entities = []
      selected_entities = []
      explicit_entity_by_constant = {}
      output_diagnostics = []
      domain.records.each do |record|
        model = model_for(record)
        entity, record_diagnostics = probe_record(domain.domain_id, record, model)
        if entity
          entities << entity
          selected_entities << { entity: entity, model: model, record: record }
          explicit_entity_by_constant[record.ruby_constant] = entity
        end
        output_diagnostics.concat(record_diagnostics)
      end
      delegated_type_families, expanded_entities, delegated_diagnostics = probe_delegated_type_families(
        domain: domain,
        explicit_selected_entities: selected_entities,
        explicit_entity_by_constant: explicit_entity_by_constant,
        explicit_selected_constants: domain.records.map(&:ruby_constant),
        records_by_constant: records_by_constant,
        owned_domain_ids_by_constant: owned_domain_ids_by_constant
      )
      output_diagnostics.concat(delegated_diagnostics)

      all_entities = entities + expanded_entities
      connection_diagnostic = entity_identity_collision_diagnostic(domain.domain_id, all_entities)
      return domain_result(domain, [], [connection_diagnostic]) if connection_diagnostic

      domain_result(
        domain,
        all_entities,
        output_diagnostics,
        probe_join_tables(selected_entities),
        probe_sti_subtypes(selected_entities, inventory_records),
        delegated_type_families
      )
    end

    def domain_result(
      domain,
      entities,
      output_diagnostics,
      join_tables = [],
      sti_subtypes = [],
      delegated_type_families = []
    )
      DomainResult.new(
        domain_id: domain.domain_id, entities: entities,
        sti_subtypes: sti_subtypes,
        join_tables: join_tables,
        delegated_type_families: delegated_type_families,
        diagnostics: output_diagnostics
      )
    end

    def probe_delegated_type_families(
      domain:,
      explicit_selected_entities:,
      explicit_entity_by_constant:,
      explicit_selected_constants:,
      records_by_constant:,
      owned_domain_ids_by_constant:
    )
      expanded_cache = {}
      expanded_entities = []
      output_diagnostics = []

      families = explicit_selected_entities.flat_map do |selected|
        delegated_root_reflections(selected.fetch(:model)).filter_map do |reflection|
          build_delegated_type_family(
            domain: domain,
            selected: selected,
            reflection: reflection,
            explicit_entity_by_constant: explicit_entity_by_constant,
            explicit_selected_constants: explicit_selected_constants,
            expanded_cache: expanded_cache,
            expanded_entities: expanded_entities,
            output_diagnostics: output_diagnostics,
            records_by_constant: records_by_constant,
            owned_domain_ids_by_constant: owned_domain_ids_by_constant
          )
        end
      end
      families.sort_by! { |family| [family.owner_entity_id, family.association_name] }
      output_diagnostics.sort_by! do |diagnostic|
        [
          diagnostic.dig('metadata', 'ruby_constant').to_s,
          diagnostic.fetch('code').to_s,
          diagnostic.fetch('subject_id').to_s
        ]
      end

      [families, expanded_entities, output_diagnostics]
    end

    def build_delegated_type_family(
      domain:,
      selected:,
      reflection:,
      explicit_entity_by_constant:,
      explicit_selected_constants:,
      expanded_cache:,
      expanded_entities:,
      output_diagnostics:,
      records_by_constant:,
      owned_domain_ids_by_constant:
    )
      owner_entity = selected.fetch(:entity)
      owner_model = selected.fetch(:model)
      owner_record = selected.fetch(:record)
      association_name = reflection_name(reflection)
      delegated_types_method = delegated_types_method_for(owner_model, association_name)
      return unless delegated_types_method

      delegated_types = call_delegated_types_method(delegated_types_method)
      return if delegated_types.nil?

      root_result = AssociationBindingResolver.polymorphic_root(reflection)
      root_binding = root_result.binding
      foreign_key_columns = root_binding&.foreign_key_columns
      foreign_type = root_binding&.foreign_type_column
      family = DelegatedTypeFamily.new(
        owner_entity_id: entity_id_for(owner_entity.table_name),
        owner_ruby_constant: owner_entity.ruby_constant,
        association_name: association_name,
        foreign_key_columns: foreign_key_columns,
        foreign_type: foreign_type,
        scoped: scoped?(reflection),
        root_diagnostic_code: delegated_root_diagnostic_code(
          owner_entity, association_name, root_result
        ),
        targets: []
      )
      return family if family.root_diagnostic_code

      family.targets = normalized_delegated_types(delegated_types).map do |ruby_constant|
        delegated_type_target(
          domain: domain,
          owner_record: owner_record,
          ruby_constant: ruby_constant,
          explicit_entity_by_constant: explicit_entity_by_constant,
          explicit_selected_constants: explicit_selected_constants,
          expanded_cache: expanded_cache,
          expanded_entities: expanded_entities,
          output_diagnostics: output_diagnostics,
          records_by_constant: records_by_constant,
          owned_domain_ids_by_constant: owned_domain_ids_by_constant
        )
      end
      family
    end

    def delegated_type_target(
      domain:,
      owner_record:,
      ruby_constant:,
      explicit_entity_by_constant:,
      explicit_selected_constants:,
      expanded_cache:,
      expanded_entities:,
      output_diagnostics:,
      records_by_constant:,
      owned_domain_ids_by_constant:
    )
      if excluded_ruby_constants(domain).include?(ruby_constant)
        return delegated_target(ruby_constant, nil, :excluded, 'DOMAIN_RELATIONSHIP_OMITTED')
      end

      record = records_by_constant[ruby_constant]
      return delegated_target(ruby_constant, nil, :unresolved, 'ASSOCIATION_TARGET_UNRESOLVED') unless record
      unless record.renderable
        return delegated_target(ruby_constant, nil, :not_renderable, 'ASSOCIATION_TARGET_NOT_RENDERABLE_OMITTED')
      end

      explicit_entity = explicit_entity_by_constant[ruby_constant]
      if explicit_entity
        unless same_connection?(owner_record, record)
          return delegated_target(
            ruby_constant, nil, :other_connection, 'CONNECTION_RELATIONSHIP_OMITTED'
          )
        end
        return delegated_target(ruby_constant, entity_id_for(explicit_entity.table_name), :selected, nil)
      end
      if explicit_selected_constants.include?(ruby_constant)
        return delegated_target(ruby_constant, nil, :not_renderable, 'ASSOCIATION_TARGET_NOT_RENDERABLE_OMITTED')
      end
      if owned_by_other_domain?(owned_domain_ids_by_constant, domain.domain_id, ruby_constant)
        return delegated_target(ruby_constant, nil, :other_domain, 'DOMAIN_RELATIONSHIP_OMITTED')
      end
      unless same_connection?(owner_record, record)
        return delegated_target(
          ruby_constant, nil, :other_connection, 'CONNECTION_RELATIONSHIP_OMITTED'
        )
      end

      expanded_probe = expanded_probe_result(
        domain.domain_id,
        record,
        expanded_cache,
        expanded_entities,
        output_diagnostics
      )
      unless expanded_probe.fetch(:entity)
        return delegated_target(ruby_constant, nil, :not_renderable, 'ASSOCIATION_TARGET_NOT_RENDERABLE_OMITTED')
      end

      delegated_target(ruby_constant, entity_id_for(expanded_probe.fetch(:entity).table_name), :expanded, nil)
    end

    def delegated_target(ruby_constant, entity_id, status, diagnostic_code)
      DelegatedTypeTarget.new(
        ruby_constant: ruby_constant,
        entity_id: entity_id,
        status: status,
        diagnostic_code: diagnostic_code
      )
    end

    def expanded_probe_result(domain_id, record, expanded_cache, expanded_entities, output_diagnostics)
      return expanded_cache[record.ruby_constant] if expanded_cache.key?(record.ruby_constant)

      entity, diagnostics = probe_record(
        domain_id,
        record,
        model_for(record),
        selection_origin: :delegated_type_expanded
      )
      expanded_entities << entity if entity
      output_diagnostics.concat(diagnostics)
      expanded_cache[record.ruby_constant] = { entity: entity, diagnostics: diagnostics }
    end

    def delegated_root_reflections(model)
      return [] unless model.respond_to?(:reflect_on_all_associations)

      Array(model.reflect_on_all_associations).select do |reflection|
        reflection_macro(reflection) == :belongs_to && polymorphic?(reflection)
      end
    rescue LoadError, SyntaxError, StandardError
      []
    end

    def delegated_types_method_for(owner_model, association_name)
      runtime_source = delegated_type_runtime_source
      return unless runtime_source

      types_method = owner_model.method("#{association_name}_types")
      source_file = types_method.source_location&.first
      return unless source_file && source_file == runtime_source

      types_method
    rescue LoadError, SyntaxError, StandardError
      nil
    end

    def delegated_type_runtime_source
      return @delegated_type_runtime_source if defined?(@delegated_type_runtime_source)

      @delegated_type_runtime_source = ActiveRecord::DelegatedType
                                       .instance_method(:delegated_type)
                                       .source_location
                                       &.first
    rescue LoadError, SyntaxError, StandardError
      @delegated_type_runtime_source = nil
    end

    def normalized_delegated_types(values)
      Array(values).filter_map do |value|
        next unless value.is_a?(String) || value.is_a?(Symbol)

        normalized = value.to_s
        normalized unless normalized.empty?
      end.uniq.sort
    end

    def call_delegated_types_method(types_method)
      types_method.call
    rescue LoadError, SyntaxError, StandardError
      nil
    end

    def delegated_root_diagnostic_code(owner_entity, association_name, root_result)
      sanitized_name = sanitize_association_name(association_name)
      return 'ASSOCIATION_NAME_UNSUPPORTED_OMITTED' unless sanitized_name
      return root_result.diagnostic_code unless root_result.success?

      root_binding = root_result.binding
      foreign_key_columns = root_binding.foreign_key_columns
      foreign_type = root_binding.foreign_type_column
      unless owner_has_key_columns?(owner_entity, foreign_key_columns, foreign_type)
        return 'ASSOCIATION_KEY_COLUMN_MISSING'
      end

      nil
    end

    def excluded_ruby_constants(domain)
      Array(safe_value_from(domain, :excluded_ruby_constants)).select { |value| present_string?(value) }.uniq
    end

    def same_connection?(owner_record, candidate_record)
      owner_record.connection_context_id == candidate_record.connection_context_id
    end

    def owned_by_other_domain?(owned_domain_ids_by_constant, domain_id, ruby_constant)
      owned_domain_ids = Array(owned_domain_ids_by_constant[ruby_constant])
                         .select { |value| present_string?(value) }
                         .uniq
      !owned_domain_ids.empty? && !owned_domain_ids.include?(domain_id)
    end

    def reflection_macro(reflection)
      safe_value_from(reflection, :macro)
    end

    def reflection_name(reflection)
      safe_value_from(reflection, :name).to_s
    end

    def polymorphic?(reflection)
      safe_value_from(reflection, :polymorphic?) == true
    end

    def scoped?(reflection)
      !!safe_value_from(reflection, :scope)
    end

    def sanitize_association_name(name)
      return unless name.match?(ASSOCIATION_NAME_PATTERN)

      name.delete_suffix('?').delete_suffix('!').delete_suffix('=')
    end

    def owner_has_key_columns?(owner_entity, foreign_key_columns, foreign_type)
      column_names = owner_entity.columns.map(&:name)
      foreign_key_columns.all? { |column| column_names.include?(column) } && column_names.include?(foreign_type)
    end

    def probe_sti_subtypes(selected_entities, inventory_records)
      selected_entities.flat_map do |selected|
        sti_subtypes_for(selected.fetch(:record), selected.fetch(:model), selected.fetch(:entity), inventory_records)
      end
    end

    def sti_subtypes_for(base_record, base_model, base_entity, inventory_records)
      base_metadata = sti_base_metadata(base_record, base_model, base_entity)
      return [] unless base_metadata

      candidates = sti_candidates(base_record, base_model, base_metadata, inventory_records)
      accepted_by_model = candidates.to_h { |candidate| [candidate.fetch(:model), candidate] }
      subtypes = candidates.filter_map do |candidate|
        sti_subtype(candidate, accepted_by_model, base_model, base_metadata.fetch(:entity_id))
      end

      subtypes.sort_by { |subtype| [subtype.depth, subtype.entity_id] }
    end

    def sti_base_metadata(base_record, base_model, base_entity)
      table_name = safe_string_value(base_model, :table_name) || base_record.table_name
      inheritance_column = safe_string_value(base_model, :inheritance_column)
      return unless present_string?(table_name) && present_string?(inheritance_column)

      {
        entity_id: entity_id_for(base_entity.table_name),
        table_name: table_name,
        inheritance_column: inheritance_column
      }
    end

    def sti_candidates(base_record, base_model, base_metadata, inventory_records)
      inventory_records.sort_by(&:ruby_constant).filter_map do |candidate_record|
        build_sti_candidate(
          base_record: base_record,
          base_model: base_model,
          base_metadata: base_metadata,
          candidate_record: candidate_record
        )
      end
    end

    def build_sti_candidate(base_record:, base_model:, base_metadata:, candidate_record:)
      return unless candidate_record_matches_base?(base_record, candidate_record)

      candidate_model = model_for(candidate_record)
      return unless candidate_model_matches_base?(candidate_model, candidate_record.ruby_constant, base_model)

      candidate_metadata = sti_candidate_metadata(candidate_model, base_metadata)
      return unless candidate_metadata

      {
        model: candidate_model,
        entity_id: sti_entity_id(base_metadata.fetch(:entity_id), candidate_record.ruby_constant),
        ruby_constant: candidate_record.ruby_constant,
        table_name: candidate_metadata.fetch(:table_name),
        inheritance_column: candidate_metadata.fetch(:inheritance_column),
        sti_name: candidate_metadata.fetch(:sti_name)
      }
    end

    def candidate_record_matches_base?(base_record, candidate_record)
      candidate_record.ruby_constant != base_record.ruby_constant &&
        candidate_record.connection_context_id == base_record.connection_context_id
    end

    def candidate_model_matches_base?(candidate_model, ruby_constant, base_model)
      named_model?(candidate_model, ruby_constant) &&
        safe_value_equals?(candidate_model, :base_class, base_model)
    end

    def sti_candidate_metadata(candidate_model, base_metadata)
      metadata = sti_candidate_scalar_metadata(candidate_model)
      return unless metadata
      return unless metadata.fetch(:table_name) == base_metadata.fetch(:table_name)
      return unless metadata.fetch(:inheritance_column) == base_metadata.fetch(:inheritance_column)

      metadata
    end

    def sti_candidate_scalar_metadata(candidate_model)
      table_name = safe_string_value(candidate_model, :table_name)
      inheritance_column = safe_string_value(candidate_model, :inheritance_column)
      sti_name = safe_string_value(candidate_model, :sti_name)
      return unless present_string?(table_name) && present_string?(inheritance_column) && present_string?(sti_name)
      return unless safe_boolean_value(candidate_model, :descends_from_active_record?) == false
      return unless safe_boolean_value(candidate_model, :abstract_class?) == false

      { table_name: table_name, inheritance_column: inheritance_column, sti_name: sti_name }
    end

    def sti_subtype(candidate, accepted_by_model, base_model, base_entity_id)
      parent = sti_parent(candidate.fetch(:model), accepted_by_model, base_model, base_entity_id)
      return unless parent

      StiSubtype.new(
        entity_id: candidate.fetch(:entity_id),
        base_entity_id: base_entity_id,
        parent_entity_id: parent.fetch(:parent_entity_id),
        ruby_constant: candidate.fetch(:ruby_constant),
        table_name: candidate.fetch(:table_name),
        inheritance_column: candidate.fetch(:inheritance_column),
        sti_name: candidate.fetch(:sti_name),
        depth: parent.fetch(:depth)
      )
    end

    def sti_parent(candidate_model, accepted_by_model, base_model, base_entity_id)
      current = candidate_model
      visible_depth = 1
      parent_entity_id = nil
      visited = {}

      loop do
        current = safe_value_from(current, :superclass)
        return unless current

        object_id = current.object_id
        return if visited.key?(object_id)

        visited[object_id] = true
        if current.equal?(base_model)
          return { parent_entity_id: parent_entity_id || base_entity_id, depth: visible_depth }
        end

        accepted_parent = accepted_by_model[current]
        next unless accepted_parent

        parent_entity_id ||= accepted_parent.fetch(:entity_id)
        visible_depth += 1
      end
    end

    def entity_id_for(table_name)
      "entities/#{table_name}"
    end

    def sti_entity_id(base_entity_id, ruby_constant)
      "#{base_entity_id}/sti/#{ruby_constant}"
    end

    def named_model?(model, expected_name)
      safe_string_value(model, :name) == expected_name
    end

    def safe_value_equals?(object, method_name, expected)
      safe_value_from(object, method_name).equal?(expected)
    end

    def safe_string_value(object, method_name)
      value = safe_value_from(object, method_name)
      value if present_string?(value)
    end

    def safe_boolean_value(object, method_name)
      value = safe_value_from(object, method_name)
      value if [true, false].include?(value)
    end

    def present_string?(value)
      value.is_a?(String) && !value.empty?
    end

    def multi_db_diagnostic(domain)
      entity_identity_collision_diagnostic(domain.domain_id, domain.records)
    end

    def entity_identity_collision_diagnostic(domain_id, records)
      collision_records = records.group_by(&:table_name).values.select do |group|
        group.map(&:connection_context_id).uniq.length > 1
      end.flatten
      raw_context_ids = collision_records.map(&:connection_context_id).uniq.sort
      return if raw_context_ids.empty?

      connection_context_ids = raw_context_ids.map { |context_id| redactor.sanitize(context_id) }

      diagnostics.build(
        code: 'MULTI_DB_UNSUPPORTED',
        message: "Domain #{domain_id} has colliding entity identities across connection contexts",
        subject_id: domain_id,
        metadata: { domain_id: domain_id, connection_context_ids: connection_context_ids }
      )
    end

    def probe_record(domain_id, record, model, selection_origin: nil)
      return invalid_record(domain_id, record, :table) if model.nil?

      return invalid_record(domain_id, record, :table) unless table_exists?(model)

      columns = read_columns(model)
      primary_key_columns = KeyTuple.normalize(read_primary_key(model))
      return invalid_record(domain_id, record, :table) if columns.nil?
      unless primary_key_columns&.all? { |name| columns.any? { |column| column.name == name } }
        return invalid_record(domain_id, record, :primary_key)
      end

      build_entity(domain_id, record, model, columns, primary_key_columns, selection_origin)
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

    def build_entity(domain_id, record, model, columns, primary_key_columns, selection_origin)
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
          primary_key_columns: primary_key_columns,
          foreign_keys: foreign_keys,
          indexes: indexes,
          selection_origin: selection_origin
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

    def probe_join_tables(selected_entities)
      grouped_requests = join_table_requests(selected_entities).group_by do |_model, connection_context_id, table_name|
        [connection_context_id, table_name]
      end
      tables = grouped_requests.filter_map do |(connection_context_id, table_name), requests|
        requests.lazy.filter_map do |model, _context_id, _name|
          read_join_table(model, table_name, connection_context_id)
        end.first
      end
      tables.sort_by { |table| [table.connection_context_id, table.table_name] }
    end

    def join_table_requests(selected_entities)
      selected_entities.flat_map do |selected|
        model = selected.fetch(:model)
        connection_context_id = selected.fetch(:entity).connection_context_id
        habtm_reflections(model).filter_map do |reflection|
          table_name = safe_value_from(reflection, :join_table)
          [model, connection_context_id, table_name] if table_name.is_a?(String) && !table_name.empty?
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

    def read_join_table(model, table_name, connection_context_id)
      connection = join_table_connection(model, table_name)
      return unless connection

      raw_primary_key = connection.primary_key(table_name)
      primary_key_columns = KeyTuple.normalize(raw_primary_key) unless raw_primary_key.nil?
      return if !raw_primary_key.nil? && primary_key_columns.nil?

      JoinTable.new(
        table_name: table_name,
        connection_context_id: connection_context_id,
        columns: Array(connection.columns(table_name)).map { |column| column_record(column) },
        primary_key_columns: primary_key_columns
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
      columns = KeyTuple.normalize(value_from(foreign_key, :column))
      primary_key_columns = KeyTuple.normalize(value_from(foreign_key, :primary_key))
      record = ForeignKey.new(
        from_table: value_from(foreign_key, :from_table),
        columns: columns,
        to_table: value_from(foreign_key, :to_table),
        primary_key_columns: primary_key_columns
      )
      table_names_valid = [record.from_table, record.to_table].all? { |value| present_string?(value) }
      return record if table_names_valid && KeyTuple.valid_pair?(record.columns, record.primary_key_columns)

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
  # rubocop:enable Metrics/AbcSize, Metrics/ClassLength, Metrics/CyclomaticComplexity
  # rubocop:enable Metrics/MethodLength, Metrics/ParameterLists, Metrics/PerceivedComplexity
end
