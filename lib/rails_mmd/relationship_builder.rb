# frozen_string_literal: true

require 'rails_mmd/diagnostics'

module RailsMmd
  # Builds selected-domain direct and through relationship records.
  # rubocop:disable Metrics/AbcSize, Metrics/ClassLength, Metrics/CyclomaticComplexity, Metrics/MethodLength, Metrics/PerceivedComplexity
  class RelationshipBuilder
    DomainResult = Struct.new(:domain_id, :relationships, :diagnostics, keyword_init: true)
    Relationship = Struct.new(
      :relationship_id,
      :owner_entity_id,
      :target_entity_id,
      :association_name,
      :foreign_key_column,
      :foreign_type_column,
      :owner_cardinality,
      :target_cardinality,
      keyword_init: true
    )
    Candidate = Struct.new(
      :relationship_id,
      :owner_entity_id,
      :target_entity_id,
      :association_name,
      :association_macro,
      :relationship_kind,
      :join_table_name,
      :declaration_owner_entity_id,
      :through_path,
      :foreign_key_holder_entity_id,
      :foreign_key_column,
      :foreign_type_column,
      :referenced_primary_key_column,
      :physical_key,
      :owner_foreign_key_column,
      :target_primary_key_column,
      :owner_fk_unique,
      :db_foreign_key,
      :owner_fk_nullable,
      :owner_cardinality,
      :target_cardinality,
      keyword_init: true
    )
    private_constant :Candidate
    Result = Struct.new(:domains, :diagnostics, keyword_init: true)

    ASSOCIATION_NAME_PATTERN = /\A[a-z][a-z0-9]*(?:_[a-z0-9]+)*[!?=]?\z/
    STRUCTURED_COLUMN_PATTERN = /\A[a-z][a-z0-9]*(?:_[a-z0-9]+)*\z/
    MACRO_PRIORITY = { belongs_to: 0, has_one: 1, has_many: 2 }.freeze
    ReflectionEntry = Struct.new(:owner, :reflection, keyword_init: true)
    DomainContext = Struct.new(:domain, keyword_init: false) do
      def domain_id = domain.domain_id

      def entities = domain.entities

      def join_table_by_name
        @join_table_by_name ||= Array(domain.join_tables).to_h { |table| [table.table_name, table] }
      end

      def entity_by_constant
        @entity_by_constant ||= entities.to_h { |entity| [entity.ruby_constant, entity] }
      end
    end

    def initialize(model_resolver:, diagnostics: Diagnostics.new)
      @model_resolver = model_resolver
      @diagnostics = diagnostics
    end

    def build(domains:)
      domain_results = domains.map { |domain| build_domain(domain) }

      Result.new(domains: domain_results, diagnostics: domain_results.flat_map(&:diagnostics))
    end

    private

    attr_reader :diagnostics, :model_resolver

    def build_domain(domain)
      context = DomainContext.new(domain)
      relationships = []
      output_diagnostics = []

      entries = reflection_entries(context)
      polymorphic_entries, ordinary_entries = entries.partition do |entry|
        polymorphic_inventory?(entry.reflection)
      end
      ordinary_entries.each do |entry|
        relationship, diagnostic = classify_reflection(context, entry.owner, entry.reflection)
        relationships << relationship if relationship
        output_diagnostics << diagnostic if diagnostic
      end
      polymorphic_relationships, polymorphic_diagnostics = build_polymorphic_relationships(
        context, polymorphic_entries
      )
      relationships.concat(polymorphic_relationships)
      output_diagnostics.concat(polymorphic_diagnostics)

      DomainResult.new(
        domain_id: domain.domain_id,
        relationships: deduplicate_relationships(relationships).sort_by(&:relationship_id),
        diagnostics: output_diagnostics
      )
    end

    def reflection_entries(context)
      context.entities.flat_map do |owner|
        owner_model = resolve_model(owner.ruby_constant)
        next [] unless owner_model

        association_reflections(owner_model).map do |reflection|
          ReflectionEntry.new(owner: owner, reflection: reflection)
        end
      end
    end

    def association_reflections(model)
      if model.respond_to?(:reflect_on_all_associations)
        Array(model.reflect_on_all_associations)
      elsif model.respond_to?(:reflections)
        model.reflections.values
      else
        []
      end
    end

    def classify_reflection(context, owner, reflection)
      return build_reflection(context, owner, reflection) if reflection_macro(reflection) == :belongs_to
      return build_habtm_reflection(context, owner, reflection) if habtm?(reflection)
      return build_through_reflection(context, owner, reflection) if through?(reflection)
      return build_direct_reflection(context, owner, reflection) if direct_has?(reflection)

      [nil, omitted_macro(context, owner, reflection)]
    end

    def habtm?(reflection)
      reflection_macro(reflection) == :has_and_belongs_to_many
    end

    def build_habtm_reflection(context, owner, reflection)
      association_name = reflection_name(reflection)
      sanitized_name = sanitize_association_name(association_name)
      return omitted(context, owner, association_name, 'ASSOCIATION_SCOPED_OMITTED') if scoped?(reflection)
      return omitted(context, owner, association_name, 'ASSOCIATION_NAME_UNSUPPORTED_OMITTED') unless sanitized_name

      target_model, target_constant = resolve_target(reflection)
      unless target_model
        return omitted(context, owner, sanitized_name, 'ASSOCIATION_TARGET_UNRESOLVED',
                       target_constant)
      end
      unless renderable_model?(target_model)
        return omitted(context, owner, sanitized_name,
                       'ASSOCIATION_TARGET_NOT_RENDERABLE_OMITTED', target_constant)
      end

      target = context.entity_by_constant[target_constant]
      return omitted(context, owner, sanitized_name, 'DOMAIN_RELATIONSHIP_OMITTED', target_constant) unless target

      keys = habtm_keys(reflection)
      return omitted(context, owner, sanitized_name, 'ASSOCIATION_COMPOSITE_KEY_OMITTED', target_constant) unless keys

      join_table = context.join_table_by_name[keys.fetch(:join_table)]
      invalid_reason = habtm_join_table_invalid_reason(join_table, keys)
      if invalid_reason
        return habtm_join_table_invalid(
          context, owner,
          keys.merge(association_name: sanitized_name, target_constant: target_constant),
          invalid_reason
        )
      end

      [habtm_relationship_for(owner, target, sanitized_name, keys), nil]
    end

    def habtm_keys(reflection)
      values = {
        join_table: safe_reflection_value(reflection, :join_table),
        owner_column: safe_reflection_value(reflection, :foreign_key),
        target_column: safe_reflection_value(reflection, :association_foreign_key)
      }
      return unless values.values.all? { |value| value.is_a?(String) && value.match?(STRUCTURED_COLUMN_PATTERN) }

      values
    end

    def habtm_join_table_invalid_reason(join_table, keys)
      return 'ambiguous_columns' if keys.fetch(:owner_column) == keys.fetch(:target_column)
      return 'unresolved' unless join_table
      return 'primary_key_present' unless join_table.primary_key.nil?

      actual = join_table.columns.map(&:name)
      required = [keys.fetch(:owner_column), keys.fetch(:target_column)]
      return 'join_column_missing' unless (required - actual).empty?

      'extra_columns' unless actual.sort == required.sort
    end

    def habtm_join_table_invalid(context, owner, details, reason)
      association_name = details.fetch(:association_name)
      metadata = association_metadata(context.domain_id, owner, association_name, details.fetch(:target_constant))
                 .merge(join_table: details.fetch(:join_table), reason: reason)
      [
        nil,
        diagnostics.build(
          code: 'ASSOCIATION_JOIN_TABLE_INVALID',
          message: omission_message(owner, association_name, 'ASSOCIATION_JOIN_TABLE_INVALID'),
          subject_id: "#{owner.table_name}.#{safe_subject_association(association_name)}",
          metadata: metadata
        )
      ]
    end

    def habtm_relationship_for(owner, target, association_name, keys)
      left, right = [
        [entity_id(owner), owner.table_name, keys.fetch(:owner_column)],
        [entity_id(target), target.table_name, keys.fetch(:target_column)]
      ].sort_by { |entity, _table, column| [entity, column] }
      join_table = keys.fetch(:join_table)
      relationship_id = [
        'relationships', left[1], 'habtm', join_table, left[2], right[1], right[2]
      ].join('/')
      Candidate.new(
        relationship_id: relationship_id,
        owner_entity_id: left[0],
        target_entity_id: right[0],
        association_name: association_name,
        association_macro: :has_and_belongs_to_many,
        relationship_kind: :habtm,
        join_table_name: join_table,
        declaration_owner_entity_id: entity_id(owner),
        physical_key: "habtm|#{join_table}|#{left[0]}|#{left[2]}|#{right[0]}|#{right[2]}",
        owner_cardinality: '0..many',
        target_cardinality: '0..many'
      )
    end

    def direct_has?(reflection)
      %i[has_many has_one].include?(reflection_macro(reflection))
    end

    def polymorphic_inventory?(reflection)
      polymorphic_root?(reflection) || polymorphic_inverse?(reflection)
    end

    def polymorphic_root?(reflection)
      reflection_macro(reflection) == :belongs_to && polymorphic?(reflection)
    end

    def polymorphic_inverse?(reflection)
      direct_has?(reflection) && !through?(reflection) && inverse_polymorphic?(reflection)
    end

    def build_polymorphic_relationships(context, entries)
      roots = entries.select { |entry| polymorphic_root?(entry.reflection) }
      inverses = entries.select { |entry| polymorphic_inverse?(entry.reflection) }
      relationships = []
      output_diagnostics = []
      handled_inverses = {}.compare_by_identity

      roots.each do |root|
        root_relationships, root_diagnostics, handled = build_polymorphic_root(context, root, inverses)
        relationships.concat(root_relationships)
        output_diagnostics.concat(root_diagnostics)
        handled.each { |reflection| handled_inverses[reflection] = true }
      end
      inverses.each do |entry|
        next if handled_inverses.key?(entry.reflection)

        code = scoped?(entry.reflection) ? 'ASSOCIATION_SCOPED_OMITTED' : 'ASSOCIATION_POLYMORPHIC_OMITTED'
        output_diagnostics << omitted(context, entry.owner, reflection_name(entry.reflection),
                                      code).last
      end
      [relationships, output_diagnostics]
    end

    def build_polymorphic_root(context, root, inverses)
      owner = root.owner
      reflection = root.reflection
      association_name = reflection_name(reflection)
      sanitized_name = sanitize_association_name(association_name)
      return polymorphic_failure(context, owner, association_name, 'ASSOCIATION_SCOPED_OMITTED') if scoped?(reflection)
      unless sanitized_name
        return polymorphic_failure(context, owner, association_name, 'ASSOCIATION_NAME_UNSUPPORTED_OMITTED')
      end

      keys = polymorphic_key_columns(reflection)
      return polymorphic_failure(context, owner, sanitized_name, 'ASSOCIATION_COMPOSITE_KEY_OMITTED') unless keys
      unless default_polymorphic_keys?(sanitized_name, keys)
        return polymorphic_failure(context, owner, sanitized_name, 'ASSOCIATION_POLYMORPHIC_OMITTED')
      end
      unless keys.values.all? { |column| column_names(owner).include?(column) }
        return polymorphic_failure(context, owner, sanitized_name, 'ASSOCIATION_KEY_COLUMN_MISSING')
      end

      candidates, candidate_diagnostics, handled = polymorphic_candidates(
        context, root, inverses, sanitized_name, keys
      )
      if candidates.empty?
        candidate_diagnostics << omitted(
          context, owner, sanitized_name, 'ASSOCIATION_POLYMORPHIC_TARGETS_UNRESOLVED'
        ).last
      end
      relationships = candidates.map do |candidate|
        polymorphic_relationship_for(owner, candidate.owner, sanitized_name, keys, candidate.reflection)
      end
      [relationships, candidate_diagnostics, handled]
    end

    def polymorphic_failure(context, owner, association_name, code)
      [[], [omitted(context, owner, association_name, code).last], []]
    end

    def polymorphic_key_columns(reflection)
      foreign_key = scalar_key(safe_reflection_value(reflection, :foreign_key))
      foreign_type = scalar_key(safe_reflection_value(reflection, :foreign_type))
      return unless foreign_key && foreign_type

      { foreign_key: foreign_key, foreign_type: foreign_type }
    end

    def default_polymorphic_keys?(association_name, keys)
      keys == {
        foreign_key: "#{association_name}_id",
        foreign_type: "#{association_name}_type"
      }
    end

    def polymorphic_candidates(context, root, inverses, association_name, keys)
      valid = []
      output_diagnostics = []
      handled = []
      inverses.each do |candidate|
        next unless inverse_interface(candidate.reflection) == association_name

        target_model, target_constant = resolve_target(candidate.reflection)
        next unless target_model && target_constant == root.owner.ruby_constant

        handled << candidate.reflection
        diagnostic = polymorphic_candidate_diagnostic(context, candidate, keys, target_model)
        if diagnostic
          output_diagnostics << diagnostic
        else
          valid << candidate
        end
      end
      canonical = valid.group_by { |candidate| entity_id(candidate.owner) }.values.map do |duplicates|
        duplicates.min_by do |candidate|
          [MACRO_PRIORITY.fetch(reflection_macro(candidate.reflection)), reflection_name(candidate.reflection)]
        end
      end
      [canonical, output_diagnostics, handled]
    end

    def polymorphic_candidate_diagnostic(context, candidate, root_keys, target_model)
      reflection = candidate.reflection
      association_name = reflection_name(reflection)
      if scoped?(reflection)
        return omitted(context, candidate.owner, association_name,
                       'ASSOCIATION_SCOPED_OMITTED').last
      end
      unless renderable_model?(target_model)
        return omitted(context, candidate.owner, association_name,
                       'ASSOCIATION_TARGET_NOT_RENDERABLE_OMITTED', target_model.name).last
      end

      candidate_keys = polymorphic_inverse_key_columns(reflection)
      unless candidate_keys == root_keys
        return omitted(context, candidate.owner, association_name, 'ASSOCIATION_POLYMORPHIC_OMITTED').last
      end

      primary_key = scalar_key(safe_reflection_value(reflection, :active_record_primary_key))
      unless primary_key && primary_key == candidate.owner.primary_key
        return omitted(context, candidate.owner, association_name, 'ASSOCIATION_NON_PRIMARY_KEY_OMITTED').last
      end
      return if column_names(candidate.owner).include?(primary_key)

      omitted(context, candidate.owner, association_name, 'ASSOCIATION_KEY_COLUMN_MISSING').last
    end

    def polymorphic_inverse_key_columns(reflection)
      foreign_key = scalar_key(safe_reflection_value(reflection, :foreign_key))
      foreign_type = scalar_key(safe_reflection_value(reflection, :type))
      return unless foreign_key && foreign_type

      { foreign_key: foreign_key, foreign_type: foreign_type }
    end

    def inverse_interface(reflection)
      reflection_options(reflection)[:as].to_s
    rescue LoadError, SyntaxError, StandardError
      ''
    end

    def build_direct_reflection(context, owner, reflection)
      association_name = reflection_name(reflection)
      if inverse_polymorphic?(reflection)
        return omitted(context, owner, association_name,
                       'ASSOCIATION_POLYMORPHIC_OMITTED')
      end
      return omitted(context, owner, association_name, 'ASSOCIATION_SCOPED_OMITTED') if scoped?(reflection)

      sanitized_name = sanitize_association_name(association_name)
      return omitted(context, owner, association_name, 'ASSOCIATION_NAME_UNSUPPORTED_OMITTED') unless sanitized_name

      target_model, target_constant = resolve_target(reflection)
      unless target_model
        return omitted(context, owner, sanitized_name, 'ASSOCIATION_TARGET_UNRESOLVED', target_constant)
      end
      unless renderable_model?(target_model)
        return omitted(context, owner, sanitized_name, 'ASSOCIATION_TARGET_NOT_RENDERABLE_OMITTED', target_constant)
      end

      target = context.entity_by_constant[target_constant]
      return omitted(context, owner, sanitized_name, 'DOMAIN_RELATIONSHIP_OMITTED', target_constant) unless target

      keys = direct_key_columns(reflection, owner)
      return omitted(context, owner, sanitized_name, 'ASSOCIATION_COMPOSITE_KEY_OMITTED', target_constant) unless keys
      unless keys.fetch(:referenced_primary_key) == owner.primary_key
        return omitted(context, owner, sanitized_name, 'ASSOCIATION_NON_PRIMARY_KEY_OMITTED', target_constant)
      end
      unless column_names(target).include?(keys.fetch(:foreign_key)) &&
             column_names(owner).include?(keys.fetch(:referenced_primary_key))
        return omitted(context, owner, sanitized_name, 'ASSOCIATION_KEY_COLUMN_MISSING', target_constant)
      end

      [direct_relationship_for(owner, target, sanitized_name, reflection_macro(reflection), keys), nil]
    end

    def build_through_reflection(context, owner, reflection)
      association_name = reflection_name(reflection)
      return [nil, omitted_macro(context, owner, reflection)] if explicit_through_source?(reflection)
      if through_source_type?(reflection)
        return omitted(context, owner, association_name, 'ASSOCIATION_POLYMORPHIC_OMITTED')
      end

      sanitized_name = sanitize_association_name(association_name)
      return omitted(context, owner, association_name, 'ASSOCIATION_NAME_UNSUPPORTED_OMITTED') unless sanitized_name

      through_reflection = safe_reflection_value(reflection, :through_reflection)
      return omitted(context, owner, sanitized_name, 'ASSOCIATION_THROUGH_UNRESOLVED') unless through_reflection

      source_reflection = safe_reflection_value(reflection, :source_reflection)
      return omitted(context, owner, sanitized_name, 'ASSOCIATION_SOURCE_UNRESOLVED') unless source_reflection

      source_lineage = through_source_lineage(source_reflection)
      return omitted(context, owner, sanitized_name, 'ASSOCIATION_SOURCE_UNRESOLVED') unless source_lineage

      chain = through_chain(reflection)
      return omitted(context, owner, sanitized_name, 'ASSOCIATION_SOURCE_UNRESOLVED') unless chain

      chain_omission = through_chain_omission_code(chain + source_lineage + [through_reflection])
      return [nil, omitted_macro(context, owner, reflection)] if chain_omission == 'ASSOCIATION_MACRO_OMITTED'
      return omitted(context, owner, sanitized_name, chain_omission) if chain_omission

      path_names = chain.map { |hop| sanitize_association_name(reflection_name(hop)) }
      path_names[-1] = sanitize_association_name(reflection_name(source_lineage.last))
      if path_names.any?(&:nil?)
        return omitted(context, owner, association_name,
                       'ASSOCIATION_NAME_UNSUPPORTED_OMITTED')
      end

      entities, diagnostic = through_entities(context, owner, sanitized_name, chain)
      return [nil, diagnostic] if diagnostic

      [through_relationship_for(owner, entities.last, sanitized_name, reflection_macro(reflection), path_names), nil]
    end

    def omitted_macro(context, owner, reflection)
      association_name = reflection_name(reflection)
      diagnostics.build(
        code: 'ASSOCIATION_MACRO_OMITTED',
        message: omission_message(owner, association_name, 'ASSOCIATION_MACRO_OMITTED'),
        subject_id: "#{owner.table_name}.#{safe_subject_association(association_name)}",
        metadata: association_metadata(context.domain_id, owner, association_name, nil).merge(
          association_macro: reflection_macro(reflection).to_s
        )
      )
    end

    def build_reflection(context, owner, reflection)
      association_name = reflection_name(reflection)
      sanitized_name = sanitize_association_name(association_name)
      return omitted(context, owner, association_name, 'ASSOCIATION_POLYMORPHIC_OMITTED') if polymorphic?(reflection)
      return omitted(context, owner, association_name, 'ASSOCIATION_SCOPED_OMITTED') if scoped?(reflection)

      return omitted(context, owner, association_name, 'ASSOCIATION_NAME_UNSUPPORTED_OMITTED') unless sanitized_name

      target_model, target_constant = resolve_target(reflection)
      unless target_model
        return omitted(context, owner, sanitized_name, 'ASSOCIATION_TARGET_UNRESOLVED',
                       target_constant)
      end

      unless renderable_model?(target_model)
        return omitted(context, owner, sanitized_name, 'ASSOCIATION_TARGET_NOT_RENDERABLE_OMITTED', target_constant)
      end

      target = context.entity_by_constant[target_constant]
      return omitted(context, owner, sanitized_name, 'DOMAIN_RELATIONSHIP_OMITTED', target_constant) unless target

      keys = key_columns(reflection, target)
      return omitted(context, owner, sanitized_name, 'ASSOCIATION_COMPOSITE_KEY_OMITTED', target_constant) if keys.nil?
      unless keys.fetch(:association_primary_key) == target.primary_key
        return omitted(context, owner, sanitized_name, 'ASSOCIATION_NON_PRIMARY_KEY_OMITTED', target_constant)
      end
      unless column_names(owner).include?(keys.fetch(:owner_foreign_key)) &&
             column_names(target).include?(keys.fetch(:target_primary_key))
        return omitted(context, owner, sanitized_name, 'ASSOCIATION_KEY_COLUMN_MISSING', target_constant)
      end

      [relationship_for(owner, target, sanitized_name, keys), nil]
    end

    def relationship_for(owner, target, association_name, keys)
      owner_fk = keys.fetch(:owner_foreign_key)
      target_pk = keys.fetch(:target_primary_key)
      owner_unique = unique_owner_fk?(owner, owner_fk)
      db_foreign_key = db_foreign_key?(owner, target, owner_fk, target_pk)
      owner_fk_nullable = column_nullable?(owner, owner_fk)

      Candidate.new(
        relationship_id: "relationships/#{owner.table_name}/#{association_name}",
        owner_entity_id: entity_id(owner),
        target_entity_id: entity_id(target),
        association_name: association_name,
        association_macro: :belongs_to,
        relationship_kind: :direct,
        foreign_key_holder_entity_id: entity_id(owner),
        foreign_key_column: owner_fk,
        referenced_primary_key_column: target_pk,
        physical_key: physical_key(entity_id(owner), owner_fk, entity_id(target), target_pk),
        owner_foreign_key_column: owner_fk,
        target_primary_key_column: target_pk,
        owner_fk_unique: owner_unique,
        db_foreign_key: db_foreign_key,
        owner_fk_nullable: owner_fk_nullable,
        owner_cardinality: owner_unique ? '0..1' : '0..many',
        target_cardinality: db_foreign_key && owner_fk_nullable == false ? '1..1' : '0..1'
      )
    end

    def direct_relationship_for(owner, target, association_name, macro, keys)
      foreign_key = keys.fetch(:foreign_key)
      referenced_primary_key = keys.fetch(:referenced_primary_key)
      db_foreign_key = db_foreign_key?(target, owner, foreign_key, referenced_primary_key)
      foreign_key_nullable = column_nullable?(target, foreign_key)

      Candidate.new(
        relationship_id: "relationships/#{owner.table_name}/#{association_name}",
        owner_entity_id: entity_id(owner),
        target_entity_id: entity_id(target),
        association_name: association_name,
        association_macro: macro,
        relationship_kind: :direct,
        foreign_key_holder_entity_id: entity_id(target),
        foreign_key_column: foreign_key,
        referenced_primary_key_column: referenced_primary_key,
        physical_key: physical_key(entity_id(target), foreign_key, entity_id(owner), referenced_primary_key),
        owner_foreign_key_column: foreign_key,
        target_primary_key_column: referenced_primary_key,
        owner_fk_unique: unique_owner_fk?(target, foreign_key),
        db_foreign_key: db_foreign_key,
        owner_fk_nullable: foreign_key_nullable,
        owner_cardinality: db_foreign_key && foreign_key_nullable == false ? '1..1' : '0..1',
        target_cardinality: macro == :has_one ? '0..1' : '0..many'
      )
    end

    def polymorphic_relationship_for(owner, target, association_name, keys, inverse_reflection)
      foreign_key = keys.fetch(:foreign_key)
      foreign_type = keys.fetch(:foreign_type)
      relationship_id = [
        'relationships', owner.table_name, 'polymorphic', association_name,
        foreign_key, foreign_type, target.table_name
      ].join('/')
      singular = reflection_macro(inverse_reflection) == :has_one ||
                 unique_owner_keys?(owner, [foreign_type, foreign_key])
      Candidate.new(
        relationship_id: relationship_id,
        owner_entity_id: entity_id(owner),
        target_entity_id: entity_id(target),
        association_name: association_name,
        association_macro: :belongs_to,
        relationship_kind: :polymorphic,
        foreign_key_holder_entity_id: entity_id(owner),
        foreign_key_column: foreign_key,
        foreign_type_column: foreign_type,
        referenced_primary_key_column: target.primary_key,
        physical_key: [
          'polymorphic', entity_id(owner), association_name,
          foreign_key, foreign_type, entity_id(target)
        ].join('|'),
        owner_foreign_key_column: foreign_key,
        target_primary_key_column: target.primary_key,
        owner_fk_unique: singular,
        db_foreign_key: false,
        owner_fk_nullable: column_nullable?(owner, foreign_key) || column_nullable?(owner, foreign_type),
        owner_cardinality: singular ? '0..1' : '0..many',
        target_cardinality: '0..1'
      )
    end

    def through_relationship_for(owner, target, association_name, macro, path_names)
      relationship_id = [
        'relationships', owner.table_name, 'through', *path_names, target.table_name
      ].join('/')
      Candidate.new(
        relationship_id: relationship_id,
        owner_entity_id: entity_id(owner),
        target_entity_id: entity_id(target),
        association_name: association_name,
        association_macro: macro,
        relationship_kind: :through,
        through_path: path_names,
        physical_key: "through|#{entity_id(owner)}|#{path_names.join('|')}|#{entity_id(target)}",
        owner_cardinality: '0..many',
        target_cardinality: macro == :has_one ? '0..1' : '0..many'
      )
    end

    def deduplicate_relationships(candidates)
      candidates.group_by(&:physical_key).map do |_key, duplicates|
        relationship_from(canonical_relationship(duplicates))
      end
    end

    def relationship_from(candidate)
      Relationship.new(
        relationship_id: candidate.relationship_id,
        owner_entity_id: candidate.owner_entity_id,
        target_entity_id: candidate.target_entity_id,
        association_name: candidate.association_name,
        foreign_key_column: candidate.foreign_key_column,
        foreign_type_column: candidate.foreign_type_column,
        owner_cardinality: candidate.owner_cardinality,
        target_cardinality: candidate.target_cardinality
      )
    end

    def canonical_relationship(candidates)
      return canonical_through_relationship(candidates) if candidates.first.relationship_kind == :through
      return candidates.min_by(&:relationship_id) if candidates.first.relationship_kind == :polymorphic
      return canonical_habtm_relationship(candidates) if candidates.first.relationship_kind == :habtm

      winner = candidates.min_by do |candidate|
        [MACRO_PRIORITY.fetch(candidate.association_macro), candidate.relationship_id]
      end
      holder_id = winner.foreign_key_holder_entity_id
      referenced_id = referenced_entity_id(winner)
      canonical = winner.dup
      canonical.relationship_id = canonical_relationship_id(winner, holder_id, referenced_id)
      canonical.owner_entity_id = holder_id
      canonical.target_entity_id = referenced_id
      canonical.owner_cardinality = canonical_holder_cardinality(candidates)
      canonical.target_cardinality = canonical_referenced_cardinality(candidates)
      canonical
    end

    def canonical_habtm_relationship(candidates)
      candidates.min_by do |candidate|
        owner_priority = candidate.declaration_owner_entity_id == candidate.owner_entity_id ? 0 : 1
        [owner_priority, candidate.association_name, candidate.relationship_id]
      end
    end

    def canonical_through_relationship(candidates)
      candidates.min_by do |candidate|
        [MACRO_PRIORITY.fetch(candidate.association_macro), candidate.association_name, candidate.relationship_id]
      end
    end

    def referenced_entity_id(relationship)
      return relationship.target_entity_id if relationship.foreign_key_holder_entity_id == relationship.owner_entity_id

      relationship.owner_entity_id
    end

    def canonical_relationship_id(relationship, holder_id, referenced_id)
      [
        'relationships', entity_table(holder_id), relationship.foreign_key_column,
        entity_table(referenced_id), relationship.referenced_primary_key_column
      ].join('/')
    end

    def entity_table(entity_id)
      entity_id.delete_prefix('entities/')
    end

    def canonical_holder_cardinality(candidates)
      singular = candidates.any? { |candidate| candidate.association_macro == :has_one || candidate.owner_fk_unique }
      singular ? '0..1' : '0..many'
    end

    def canonical_referenced_cardinality(candidates)
      required = candidates.any? { |candidate| candidate.db_foreign_key && candidate.owner_fk_nullable == false }
      required ? '1..1' : '0..1'
    end

    def physical_key(holder_id, foreign_key, referenced_id, primary_key)
      [holder_id, foreign_key, referenced_id, primary_key].join('|')
    end

    def omitted(context, owner, association_name, code, target_constant = nil)
      [
        nil,
        diagnostics.build(
          code: code,
          message: omission_message(owner, association_name, code),
          subject_id: "#{owner.table_name}.#{safe_subject_association(association_name)}",
          metadata: association_metadata(context.domain_id, owner, association_name, target_constant)
        )
      ]
    end

    def omission_message(owner, association_name, code)
      "#{owner.ruby_constant}.#{association_name} omitted: #{code.downcase}"
    end

    def association_metadata(domain_id, owner, association_name, target_constant)
      metadata = {
        domain_id: domain_id,
        owner_constant: owner.ruby_constant,
        association_name: association_name.to_s
      }
      metadata[:target_constant] = target_constant if target_constant
      metadata
    end

    def resolve_target(reflection)
      target_model = target_model_for(reflection)
      [target_model, target_model.respond_to?(:name) ? target_model.name : reflection_class_name(reflection)]
    rescue LoadError, SyntaxError, StandardError
      [nil, reflection_class_name(reflection)]
    end

    def target_model_for(reflection)
      return model_resolver.call(reflection_class_name(reflection)) unless reflection.respond_to?(:klass)

      reflection.klass
    rescue NameError
      model_resolver.call(reflection_class_name(reflection))
    end

    def resolve_model(ruby_constant)
      model_resolver.call(ruby_constant)
    rescue LoadError, SyntaxError, StandardError
      nil
    end

    def renderable_model?(model)
      return false if model.respond_to?(:abstract_class?) && model.abstract_class?
      return false if model.respond_to?(:base_class) && model.base_class != model

      model.respond_to?(:table_name) && model.table_name.to_s != ''
    rescue LoadError, SyntaxError, StandardError
      false
    end

    def key_columns(reflection, target)
      owner_foreign_key = scalar_key(reflection_value(reflection, :foreign_key))
      association_primary_key = scalar_key(reflection_value(reflection, :association_primary_key))
      target_primary_key = scalar_key(target.primary_key)
      return unless owner_foreign_key && association_primary_key && target_primary_key

      {
        owner_foreign_key: owner_foreign_key,
        association_primary_key: association_primary_key,
        target_primary_key: target_primary_key
      }
    end

    def direct_key_columns(reflection, owner)
      foreign_key = scalar_key(reflection_value(reflection, :foreign_key))
      referenced_primary_key = scalar_key(reflection_value(reflection, :active_record_primary_key))
      referenced_primary_key ||= scalar_key(owner.primary_key)
      return unless foreign_key && referenced_primary_key

      { foreign_key: foreign_key, referenced_primary_key: referenced_primary_key }
    rescue LoadError, SyntaxError, StandardError
      nil
    end

    def unique_owner_fk?(owner, owner_fk)
      owner.indexes.any? do |index|
        index.unique == true &&
          Array(index.columns) == [owner_fk] &&
          total_plain_index?(index)
      end
    end

    def unique_owner_keys?(owner, key_columns)
      owner.indexes.any? do |index|
        index.unique == true &&
          Array(index.columns).sort == key_columns.sort &&
          total_plain_index?(index)
      end
    end

    def total_plain_index?(index)
      index.where.nil? && index.expression.nil? && [nil, 'btree', :btree].include?(index.using)
    end

    def db_foreign_key?(owner, target, owner_fk, target_pk)
      owner.foreign_keys.any? do |foreign_key|
        foreign_key.from_table == owner.table_name &&
          foreign_key.column == owner_fk &&
          foreign_key.to_table == target.table_name &&
          foreign_key.primary_key == target_pk
      end
    end

    def column_nullable?(entity, column_name)
      entity.columns.find { |column| column.name == column_name }&.nullable
    end

    def column_names(entity)
      entity.columns.map(&:name)
    end

    def reflection_value(reflection, method_name)
      return unless reflection.respond_to?(method_name)

      reflection.public_send(method_name)
    end

    def safe_reflection_value(reflection, method_name)
      reflection_value(reflection, method_name)
    rescue LoadError, SyntaxError, StandardError
      nil
    end

    def reflection_options(reflection)
      reflection.respond_to?(:options) ? reflection.options : {}
    end

    def explicit_through_source?(reflection)
      reflection_options(reflection).key?(:source)
    end

    def through_source_type?(reflection)
      !reflection_options(reflection)[:source_type].nil?
    end

    def through_scoped?(reflection)
      return !!reflection.has_scope? if reflection.respond_to?(:has_scope?)

      scoped?(reflection)
    end

    def through_chain(reflection)
      chain = Array(reflection.collect_join_chain).reverse
      chain unless chain.empty?
    rescue LoadError, SyntaxError, StandardError
      nil
    end

    def through_source_lineage(source_reflection)
      lineage = []
      seen = {}.compare_by_identity
      current = source_reflection
      loop do
        return if seen.key?(current)

        seen[current] = true
        lineage << current
        break if explicit_through_source?(current) || through_source_type?(current) || polymorphic?(current)
        break unless through?(current)

        current = safe_reflection_value(current, :source_reflection)
        return unless current
      end
      lineage
    rescue LoadError, SyntaxError, StandardError
      nil
    end

    def through_chain_omission_code(chain)
      return 'ASSOCIATION_MACRO_OMITTED' if chain.any? { |hop| explicit_through_source?(hop) }
      return 'ASSOCIATION_POLYMORPHIC_OMITTED' if chain.any? { |hop| through_source_type?(hop) || polymorphic?(hop) }
      return 'ASSOCIATION_SCOPED_OMITTED' if chain.any? { |hop| through_scoped?(hop) || scoped?(hop) }

      nil
    rescue LoadError, SyntaxError, StandardError
      'ASSOCIATION_SOURCE_UNRESOLVED'
    end

    def through_entities(context, owner, association_name, chain)
      entities = []
      chain.each_with_index do |hop, index|
        model, constant = resolve_target(hop)
        code = index.zero? ? 'ASSOCIATION_THROUGH_UNRESOLVED' : 'ASSOCIATION_SOURCE_UNRESOLVED'
        return [nil, omitted(context, owner, association_name, code, constant).last] unless model
        unless renderable_model?(model)
          return [nil, omitted(context, owner, association_name,
                               'ASSOCIATION_TARGET_NOT_RENDERABLE_OMITTED', constant).last]
        end

        entity = context.entity_by_constant[constant]
        unless entity
          return [nil,
                  omitted(context, owner, association_name, 'DOMAIN_RELATIONSHIP_OMITTED', constant).last]
        end

        entities << entity
      end
      [entities, nil]
    end

    def scalar_key(value)
      value if value.is_a?(String) && !value.empty?
    end

    def reflection_name(reflection)
      reflection.respond_to?(:name) ? reflection.name.to_s : ''
    end

    def reflection_class_name(reflection)
      return reflection.class_name if reflection.respond_to?(:class_name)

      reflection_name(reflection).split('_').map(&:capitalize).join
    end

    def reflection_macro(reflection)
      reflection.respond_to?(:macro) ? reflection.macro : nil
    end

    def polymorphic?(reflection)
      reflection.respond_to?(:polymorphic?) && reflection.polymorphic?
    end

    def scoped?(reflection)
      reflection.respond_to?(:scope) && !!reflection.scope
    end

    def through?(reflection)
      reflection.respond_to?(:through_reflection?) && reflection.through_reflection?
    end

    def inverse_polymorphic?(reflection)
      reflection.respond_to?(:type) && !reflection.type.nil?
    end

    def sanitize_association_name(name)
      return unless name.match?(ASSOCIATION_NAME_PATTERN)

      name.delete_suffix('?').delete_suffix('!').delete_suffix('=')
    end

    def safe_subject_association(name)
      sanitized = sanitize_association_name(name.to_s)
      sanitized || 'unsupported'
    end

    def entity_id(entity)
      "entities/#{entity.table_name}"
    end
  end
  # rubocop:enable Metrics/AbcSize, Metrics/ClassLength, Metrics/CyclomaticComplexity, Metrics/MethodLength, Metrics/PerceivedComplexity
end
