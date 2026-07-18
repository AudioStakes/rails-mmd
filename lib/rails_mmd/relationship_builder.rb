# frozen_string_literal: true

require 'rails_mmd/canonical_json'
require 'rails_mmd/diagnostics'
require 'rails_mmd/key_tuple'
require 'rails_mmd/relationship_id_codec'

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
      :association_macro,
      :relationship_kind,
      :join_table_name,
      :declaration_owner_entity_id,
      :through_path,
      :foreign_key_holder_entity_id,
      :foreign_key_columns,
      :foreign_type_column,
      :referenced_key_columns,
      :physical_key,
      :owner_fk_unique,
      :db_foreign_key,
      :owner_fk_nullable,
      :owner_cardinality,
      :target_cardinality,
      :metadata,
      keyword_init: true
    )
    Result = Struct.new(:domains, :diagnostics, keyword_init: true) do
      def success?
        true
      end
    end

    ASSOCIATION_NAME_PATTERN = /\A[a-z][a-z0-9]*(?:_[a-z0-9]+)*[!?=]?\z/
    STRUCTURED_COLUMN_PATTERN = /\A[a-z][a-z0-9]*(?:_[a-z0-9]+)*\z/
    MACRO_PRIORITY = { belongs_to: 0, has_one: 1, has_many: 2 }.freeze
    ReflectionEntry = Struct.new(:owner, :reflection, :metadata, :referenced_key_columns, keyword_init: true)
    DomainContext = Struct.new(:domain, keyword_init: false) do
      def domain_id = domain.domain_id

      def entities = domain.entities

      def owner_entities
        @owner_entities ||= entities.reject do |entity|
          selection_origin = safe_value(entity, :selection_origin)
          selection_origin == :delegated_type_expanded
        end
      end

      def join_table_by_name
        @join_table_by_name ||= Array(domain.join_tables).to_h { |table| [table.table_name, table] }
      end

      def entity_by_constant
        @entity_by_constant ||= entities.to_h { |entity| [entity.ruby_constant, entity] }
      end

      def entity_by_id
        @entity_by_id ||= entities.to_h { |entity| ["entities/#{entity.table_name}", entity] }
      end

      def delegated_type_families
        @delegated_type_families ||= begin
          families = safe_value(domain, :delegated_type_families)
          Array(families)
        end
      end

      private

      def safe_value(object, method_name)
        return unless object.respond_to?(method_name)

        object.public_send(method_name)
      rescue LoadError, SyntaxError, StandardError
        nil
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
      context.owner_entities.flat_map do |owner|
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

      metadata = { scoped: true } if scoped?(reflection)
      [habtm_relationship_for(owner, target, sanitized_name, keys, metadata: metadata), nil]
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
      return 'primary_key_present' unless join_table.primary_key_columns.nil?

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

    def habtm_relationship_for(owner, target, association_name, keys, metadata: nil)
      left, right = [
        [entity_id(owner), owner.table_name, keys.fetch(:owner_column)],
        [entity_id(target), target.table_name, keys.fetch(:target_column)]
      ].sort_by { |entity, _table, column| [entity, column] }
      join_table = keys.fetch(:join_table)
      relationship_id = [
        'relationships', left[1], 'habtm', join_table, left[2], right[1], right[2]
      ].join('/')
      Relationship.new(
        relationship_id: relationship_id,
        owner_entity_id: left[0],
        target_entity_id: right[0],
        association_name: association_name,
        association_macro: :has_and_belongs_to_many,
        relationship_kind: :habtm,
        join_table_name: join_table,
        declaration_owner_entity_id: entity_id(owner),
        physical_key: CanonicalJson.dump(
          kind: 'habtm',
          join_table: join_table,
          left_entity_id: left[0],
          left_column: left[2],
          right_entity_id: right[0],
          right_column: right[2]
        ),
        owner_cardinality: '0..many',
        target_cardinality: '0..many',
        metadata: metadata
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

        output_diagnostics << omitted(context, entry.owner, reflection_name(entry.reflection),
                                      'ASSOCIATION_POLYMORPHIC_OMITTED').last
      end
      [relationships, output_diagnostics]
    end

    def build_polymorphic_root(context, root, inverses)
      owner = root.owner
      reflection = root.reflection
      association_name = reflection_name(reflection)
      sanitized_name = sanitize_association_name(association_name)
      unless sanitized_name
        return polymorphic_failure(context, owner, association_name, 'ASSOCIATION_NAME_UNSUPPORTED_OMITTED')
      end

      family = delegated_type_family(context, owner, sanitized_name)
      if family
        root_diagnostic_code = delegated_family_root_diagnostic_code(family)
        return polymorphic_failure(context, owner, sanitized_name, root_diagnostic_code) if root_diagnostic_code
      end

      keys = polymorphic_key_columns(reflection)
      return polymorphic_failure(context, owner, sanitized_name, 'ASSOCIATION_COMPOSITE_KEY_OMITTED') unless keys
      unless supported_polymorphic_key_names?(sanitized_name, keys)
        return polymorphic_failure(context, owner, sanitized_name, 'ASSOCIATION_POLYMORPHIC_OMITTED')
      end
      unless columns_present?(owner, keys.fetch(:foreign_key_columns)) &&
             column_names(owner).include?(keys.fetch(:foreign_type))
        return polymorphic_failure(context, owner, sanitized_name, 'ASSOCIATION_KEY_COLUMN_MISSING')
      end

      candidates, candidate_diagnostics, handled =
        if family
          delegated_polymorphic_candidates(
            context,
            root,
            inverses,
            family,
            { association_name: sanitized_name, keys: keys }
          )
        else
          polymorphic_candidates(context, root, inverses, sanitized_name, keys)
        end
      if candidates.empty?
        candidate_diagnostics << omitted(
          context, owner, sanitized_name, 'ASSOCIATION_POLYMORPHIC_TARGETS_UNRESOLVED'
        ).last
      end
      root_metadata = { scoped: true } if scoped?(reflection)
      relationships = candidates.map do |candidate|
        metadata = candidate.metadata || root_metadata
        relationship = polymorphic_relationship_for(owner, candidate.owner, sanitized_name, keys, candidate)
        relationship_with_metadata(relationship, metadata)
      end
      [relationships, candidate_diagnostics, handled]
    end

    def polymorphic_failure(context, owner, association_name, code)
      [[], [omitted(context, owner, association_name, code).last], []]
    end

    def polymorphic_key_columns(reflection)
      foreign_key_columns = KeyTuple.normalize(safe_reflection_value(reflection, :foreign_key))
      foreign_type = scalar_key(safe_reflection_value(reflection, :foreign_type))
      return unless foreign_key_columns && foreign_type

      { foreign_key_columns: foreign_key_columns, foreign_type: foreign_type }
    end

    def supported_polymorphic_key_names?(association_name, keys)
      return false unless keys.fetch(:foreign_type) == "#{association_name}_type"

      columns = keys.fetch(:foreign_key_columns)
      columns.length > 1 || columns == ["#{association_name}_id"]
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
        diagnostic = polymorphic_candidate_diagnostic(context, root, candidate, keys, target_model)
        if diagnostic
          output_diagnostics << diagnostic
        else
          valid << candidate
        end
      end
      canonical = canonical_polymorphic_candidates(valid)
      [canonical, output_diagnostics, handled]
    end

    def delegated_polymorphic_candidates(context, root, inverses, family, root_details)
      diagnostics = []
      handled = []
      candidates = []
      candidate_context = { inverses: inverses, family: family, root_details: root_details }

      delegated_family_targets(family).each do |target|
        candidate, target_diagnostics, target_handled = delegated_target_candidate(
          context, root, target, candidate_context
        )
        diagnostics.concat(target_diagnostics)
        handled.concat(target_handled)
        candidates << candidate if candidate
      end

      [candidates, diagnostics, handled]
    end

    def delegated_target_candidate(context, root, target, candidate_context)
      inverses = candidate_context.fetch(:inverses)
      family = candidate_context.fetch(:family)
      root_details = candidate_context.fetch(:root_details)
      target_constant = delegated_target_ruby_constant(target)
      diagnostic_code = delegated_target_diagnostic_code(target)
      if diagnostic_code
        diagnostic = omitted(
          context, root.owner, root_details.fetch(:association_name), diagnostic_code, target_constant
        ).last
        return [nil, [diagnostic], []]
      end

      target_entity = delegated_target_entity(context, target)
      return [nil, [], []] unless target_entity

      valid_inverses, target_diagnostics, target_handled = delegated_inverse_candidates(
        context, root, inverses, root_details, target_entity
      )
      chosen_inverse = canonical_polymorphic_candidates(valid_inverses).first
      referenced_key_columns = chosen_inverse&.referenced_key_columns ||
                               polymorphic_referenced_key_columns(root.reflection, target_entity)
      root_foreign_key_columns = root_details.fetch(:keys).fetch(:foreign_key_columns)
      unless KeyTuple.valid_pair?(root_foreign_key_columns, referenced_key_columns)
        diagnostic = omitted(
          context, root.owner, root_details.fetch(:association_name),
          'ASSOCIATION_COMPOSITE_KEY_OMITTED', target_constant
        ).last
        return [nil, target_diagnostics + [diagnostic], target_handled]
      end
      unless columns_present?(target_entity, referenced_key_columns)
        diagnostic = omitted(
          context, root.owner, root_details.fetch(:association_name),
          'ASSOCIATION_KEY_COLUMN_MISSING', target_constant
        ).last
        return [nil, target_diagnostics + [diagnostic], target_handled]
      end

      candidate = ReflectionEntry.new(
        owner: target_entity,
        reflection: chosen_inverse&.reflection,
        metadata: delegated_relationship_metadata(root.reflection, family, valid_inverses),
        referenced_key_columns: referenced_key_columns
      )
      [candidate, target_diagnostics, target_handled]
    end

    def delegated_inverse_candidates(context, root, inverses, root_details, target_entity)
      candidates, handled = delegated_inverse_entries(
        inverses,
        root_details.fetch(:association_name),
        target_entity
      )
      valid = []
      diagnostics = []

      candidates.each do |candidate|
        handled << candidate.reflection if inverses.include?(candidate)
        target_model, resolution_diagnostic = delegated_inverse_target(context, root, candidate)
        if resolution_diagnostic
          diagnostics << resolution_diagnostic
          next
        end

        diagnostic = polymorphic_candidate_diagnostic(
          context,
          root,
          candidate,
          root_details.fetch(:keys),
          target_model
        )
        if diagnostic
          diagnostics << diagnostic
        else
          valid << candidate
        end
      end

      [valid, diagnostics, handled]
    end

    def delegated_inverse_target(context, root, candidate)
      target_model, target_constant = resolve_target(candidate.reflection)
      unless target_model
        diagnostic = omitted(
          context, candidate.owner, reflection_name(candidate.reflection),
          'ASSOCIATION_TARGET_UNRESOLVED', target_constant
        ).last
        return [nil, diagnostic]
      end
      return [target_model, nil] if target_constant == root.owner.ruby_constant

      diagnostic = omitted(
        context, candidate.owner, reflection_name(candidate.reflection),
        'ASSOCIATION_POLYMORPHIC_OMITTED'
      ).last
      [nil, diagnostic]
    end

    def delegated_inverse_entries(inverses, association_name, target_entity)
      explicit_entries = inverses.select do |entry|
        entry.owner.equal?(target_entity) && inverse_interface(entry.reflection) == association_name
      end
      return [explicit_entries, []] unless explicit_entries.empty?

      target_model = resolve_model(target_entity.ruby_constant)
      return [[], []] unless target_model

      targeted = association_reflections(target_model).filter_map do |reflection|
        next unless polymorphic_inverse?(reflection)
        next unless inverse_interface(reflection) == association_name

        ReflectionEntry.new(owner: target_entity, reflection: reflection)
      end
      [targeted, []]
    end

    def delegated_relationship_metadata(root_reflection, family, valid_inverses)
      scoped = scoped?(root_reflection) || delegated_family_scoped?(family) ||
               valid_inverses.any? { |candidate| scoped?(candidate.reflection) }
      { scoped: true } if scoped
    end

    def canonical_polymorphic_candidates(candidates)
      candidates.group_by { |candidate| entity_id(candidate.owner) }.values.map do |duplicates|
        winner = duplicates.min_by do |candidate|
          [MACRO_PRIORITY.fetch(reflection_macro(candidate.reflection)), reflection_name(candidate.reflection)]
        end
        winner.dup.tap do |candidate|
          candidate.metadata = { scoped: true } if duplicates.any? { |entry| scoped?(entry.reflection) }
        end
      end
    end

    def polymorphic_candidate_diagnostic(context, root, candidate, root_keys, target_model)
      reflection = candidate.reflection
      association_name = reflection_name(reflection)
      unless renderable_model?(target_model)
        return omitted(context, candidate.owner, association_name,
                       'ASSOCIATION_TARGET_NOT_RENDERABLE_OMITTED', target_model.name).last
      end

      candidate_keys = polymorphic_inverse_key_columns(reflection)
      unless candidate_keys == root_keys
        return omitted(context, candidate.owner, association_name, 'ASSOCIATION_POLYMORPHIC_OMITTED').last
      end

      referenced_key_columns = polymorphic_referenced_key_columns(root.reflection, candidate.owner)
      inverse_referenced_key_columns = KeyTuple.normalize(
        safe_reflection_value(reflection, :active_record_primary_key)
      )
      unless KeyTuple.valid_pair?(root_keys.fetch(:foreign_key_columns), referenced_key_columns) &&
             inverse_referenced_key_columns
        return omitted(context, candidate.owner, association_name, 'ASSOCIATION_COMPOSITE_KEY_OMITTED').last
      end

      unless inverse_referenced_key_columns == referenced_key_columns
        if inverse_referenced_key_columns == candidate.owner.primary_key_columns &&
           !columns_present?(candidate.owner, inverse_referenced_key_columns)
          return omitted(context, candidate.owner, association_name, 'ASSOCIATION_KEY_COLUMN_MISSING').last
        end

        return omitted(context, candidate.owner, association_name, 'ASSOCIATION_NON_PRIMARY_KEY_OMITTED').last
      end
      unless columns_present?(candidate.owner, referenced_key_columns)
        return omitted(context, candidate.owner, association_name, 'ASSOCIATION_KEY_COLUMN_MISSING').last
      end

      candidate.referenced_key_columns = referenced_key_columns
      nil
    end

    def polymorphic_inverse_key_columns(reflection)
      foreign_key_columns = KeyTuple.normalize(safe_reflection_value(reflection, :foreign_key))
      foreign_type = scalar_key(safe_reflection_value(reflection, :type))
      return unless foreign_key_columns && foreign_type

      { foreign_key_columns: foreign_key_columns, foreign_type: foreign_type }
    end

    def polymorphic_referenced_key_columns(root_reflection, target_entity)
      target_model = resolve_model(target_entity.ruby_constant)
      return unless target_model

      KeyTuple.normalize(association_primary_key(root_reflection, target_model))
    rescue LoadError, SyntaxError, StandardError
      nil
    end

    def inverse_interface(reflection)
      reflection_options(reflection)[:as].to_s
    rescue LoadError, SyntaxError, StandardError
      ''
    end

    def delegated_type_family(context, owner, association_name)
      context.delegated_type_families.find do |family|
        delegated_family_owner_entity_id(family) == entity_id(owner) &&
          delegated_family_association_name(family) == association_name
      end
    end

    def delegated_family_targets(family)
      Array(safe_value(family, :targets))
    end

    def delegated_family_root_diagnostic_code(family)
      safe_value(family, :root_diagnostic_code)
    end

    def delegated_family_owner_entity_id(family)
      safe_value(family, :owner_entity_id)
    end

    def delegated_family_association_name(family)
      safe_value(family, :association_name)
    end

    def delegated_family_scoped?(family)
      safe_value(family, :scoped) == true
    end

    def delegated_target_ruby_constant(target)
      safe_value(target, :ruby_constant)
    end

    def delegated_target_diagnostic_code(target)
      safe_value(target, :diagnostic_code)
    end

    def delegated_target_entity(context, target)
      entity = context.entity_by_id[safe_value(target, :entity_id)]
      entity || context.entity_by_constant[delegated_target_ruby_constant(target)]
    end

    def build_direct_reflection(context, owner, reflection)
      association_name = reflection_name(reflection)
      if inverse_polymorphic?(reflection)
        return omitted(context, owner, association_name,
                       'ASSOCIATION_POLYMORPHIC_OMITTED')
      end

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
      if keys == :non_primary_key
        return omitted(context, owner, sanitized_name, 'ASSOCIATION_NON_PRIMARY_KEY_OMITTED', target_constant)
      end
      unless columns_present?(target, keys.fetch(:foreign_key_columns)) &&
             columns_present?(owner, keys.fetch(:referenced_key_columns))
        return omitted(context, owner, sanitized_name, 'ASSOCIATION_KEY_COLUMN_MISSING', target_constant)
      end

      metadata = { scoped: true } if scoped?(reflection)
      relationship = direct_relationship_for(owner, target, sanitized_name, reflection_macro(reflection), keys)
      [relationship_with_metadata(relationship, metadata), nil]
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

      key_omission = through_physical_key_omission_code(context, owner, reflection)
      return omitted(context, owner, sanitized_name, key_omission) if key_omission

      scoped = scoped?(reflection) || source_lineage.any? { |hop| scoped?(hop) } || chain.any? { |hop| scoped?(hop) }
      metadata = { scoped: true } if scoped
      relationship = through_relationship_for(owner, entities.last, sanitized_name, reflection_macro(reflection),
                                              path_names)
      [relationship_with_metadata(relationship, metadata), nil]
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

      keys = key_columns(reflection, target_model)
      return omitted(context, owner, sanitized_name, 'ASSOCIATION_COMPOSITE_KEY_OMITTED', target_constant) if keys.nil?
      if reflection_options(reflection).key?(:primary_key)
        return omitted(context, owner, sanitized_name, 'ASSOCIATION_NON_PRIMARY_KEY_OMITTED', target_constant)
      end
      unless columns_present?(owner, keys.fetch(:foreign_key_columns)) &&
             columns_present?(target, keys.fetch(:referenced_key_columns))
        return omitted(context, owner, sanitized_name, 'ASSOCIATION_KEY_COLUMN_MISSING', target_constant)
      end

      metadata = { scoped: true } if scoped?(reflection)
      [relationship_for(owner, target, sanitized_name, keys, metadata: metadata), nil]
    end

    def relationship_for(owner, target, association_name, keys, metadata: nil)
      foreign_key_columns = keys.fetch(:foreign_key_columns)
      referenced_key_columns = keys.fetch(:referenced_key_columns)
      owner_unique = unique_owner_keys?(owner, foreign_key_columns)
      db_foreign_key = db_foreign_key?(owner, target, foreign_key_columns, referenced_key_columns)
      owner_fk_nullable = columns_nullable?(owner, foreign_key_columns)

      Relationship.new(
        relationship_id: RelationshipIdCodec.direct(
          holder_table: owner.table_name,
          foreign_key_columns: foreign_key_columns,
          referenced_table: target.table_name,
          referenced_key_columns: referenced_key_columns
        ),
        owner_entity_id: entity_id(owner),
        target_entity_id: entity_id(target),
        association_name: association_name,
        association_macro: :belongs_to,
        relationship_kind: :direct,
        foreign_key_holder_entity_id: entity_id(owner),
        foreign_key_columns: foreign_key_columns,
        referenced_key_columns: referenced_key_columns,
        physical_key: physical_key(entity_id(owner), foreign_key_columns, entity_id(target), referenced_key_columns),
        owner_fk_unique: owner_unique,
        db_foreign_key: db_foreign_key,
        owner_fk_nullable: owner_fk_nullable,
        owner_cardinality: owner_unique ? '0..1' : '0..many',
        target_cardinality: db_foreign_key && owner_fk_nullable == false ? '1..1' : '0..1',
        metadata: metadata
      )
    end

    def direct_relationship_for(owner, target, association_name, macro, keys)
      foreign_key_columns = keys.fetch(:foreign_key_columns)
      referenced_key_columns = keys.fetch(:referenced_key_columns)
      db_foreign_key = db_foreign_key?(target, owner, foreign_key_columns, referenced_key_columns)
      foreign_key_nullable = columns_nullable?(target, foreign_key_columns)

      Relationship.new(
        relationship_id: RelationshipIdCodec.direct(
          holder_table: target.table_name,
          foreign_key_columns: foreign_key_columns,
          referenced_table: owner.table_name,
          referenced_key_columns: referenced_key_columns
        ),
        owner_entity_id: entity_id(owner),
        target_entity_id: entity_id(target),
        association_name: association_name,
        association_macro: macro,
        relationship_kind: :direct,
        foreign_key_holder_entity_id: entity_id(target),
        foreign_key_columns: foreign_key_columns,
        referenced_key_columns: referenced_key_columns,
        physical_key: physical_key(entity_id(target), foreign_key_columns, entity_id(owner), referenced_key_columns),
        owner_fk_unique: unique_owner_keys?(target, foreign_key_columns),
        db_foreign_key: db_foreign_key,
        owner_fk_nullable: foreign_key_nullable,
        owner_cardinality: db_foreign_key && foreign_key_nullable == false ? '1..1' : '0..1',
        target_cardinality: macro == :has_one ? '0..1' : '0..many'
      )
    end

    def polymorphic_relationship_for(owner, target, association_name, keys, candidate)
      foreign_key_columns = keys.fetch(:foreign_key_columns)
      foreign_type = keys.fetch(:foreign_type)
      referenced_key_columns = candidate.referenced_key_columns
      relationship_id = RelationshipIdCodec.polymorphic(
        holder_table: owner.table_name,
        interface: association_name,
        identifier_columns: foreign_key_columns,
        type_column: foreign_type,
        target_table: target.table_name
      )
      singular = unique_owner_keys?(owner, foreign_key_columns + [foreign_type])
      Relationship.new(
        relationship_id: relationship_id,
        owner_entity_id: entity_id(owner),
        target_entity_id: entity_id(target),
        association_name: association_name,
        association_macro: :belongs_to,
        relationship_kind: :polymorphic,
        foreign_key_holder_entity_id: entity_id(owner),
        foreign_key_columns: foreign_key_columns,
        foreign_type_column: foreign_type,
        referenced_key_columns: referenced_key_columns,
        physical_key: CanonicalJson.dump(
          kind: 'polymorphic',
          holder_entity_id: entity_id(owner),
          interface: association_name,
          foreign_key_columns: foreign_key_columns,
          foreign_type_column: foreign_type,
          referenced_entity_id: entity_id(target),
          referenced_key_columns: referenced_key_columns
        ),
        owner_fk_unique: singular,
        db_foreign_key: false,
        owner_fk_nullable: columns_nullable?(owner, foreign_key_columns + [foreign_type]),
        owner_cardinality: singular ? '0..1' : '0..many',
        target_cardinality: '0..1'
      )
    end

    def through_relationship_for(owner, target, association_name, macro, path_names)
      relationship_id = [
        'relationships', owner.table_name, 'through', *path_names, target.table_name
      ].join('/')
      Relationship.new(
        relationship_id: relationship_id,
        owner_entity_id: entity_id(owner),
        target_entity_id: entity_id(target),
        association_name: association_name,
        association_macro: macro,
        relationship_kind: :through,
        through_path: path_names,
        physical_key: CanonicalJson.dump(
          kind: 'through',
          owner_entity_id: entity_id(owner),
          path: path_names,
          target_entity_id: entity_id(target)
        ),
        owner_cardinality: '0..many',
        target_cardinality: macro == :has_one ? '0..1' : '0..many'
      )
    end

    def relationship_with_metadata(relationship, metadata)
      relationship.metadata = metadata
      relationship
    end

    def deduplicate_relationships(relationships)
      relationships.group_by(&:physical_key).map do |_key, candidates|
        canonical_relationship(candidates)
      end
    end

    def canonical_relationship(candidates)
      return canonical_through_relationship(candidates) if candidates.first.relationship_kind == :through
      return canonical_polymorphic_relationship(candidates) if candidates.first.relationship_kind == :polymorphic
      return canonical_habtm_relationship(candidates) if candidates.first.relationship_kind == :habtm

      winner = candidates.min_by do |candidate|
        [MACRO_PRIORITY.fetch(candidate.association_macro), candidate.association_name, candidate.relationship_id]
      end
      holder_id = winner.foreign_key_holder_entity_id
      referenced_id = referenced_entity_id(winner)
      canonical = winner.dup
      canonical.relationship_id = canonical_relationship_id(winner, holder_id, referenced_id)
      canonical.owner_entity_id = holder_id
      canonical.target_entity_id = referenced_id
      canonical.owner_cardinality = canonical_holder_cardinality(candidates)
      canonical.target_cardinality = canonical_referenced_cardinality(candidates)
      canonical.metadata = merged_relationship_metadata(candidates)
      canonical
    end

    def canonical_polymorphic_relationship(candidates)
      winner = candidates.min_by(&:relationship_id)
      winner.dup.tap { |relationship| relationship.metadata = merged_relationship_metadata(candidates) }
    end

    def canonical_habtm_relationship(candidates)
      winner = candidates.min_by do |candidate|
        owner_priority = candidate.declaration_owner_entity_id == candidate.owner_entity_id ? 0 : 1
        [owner_priority, candidate.association_name, candidate.relationship_id]
      end
      winner.dup.tap { |relationship| relationship.metadata = merged_relationship_metadata(candidates) }
    end

    def canonical_through_relationship(candidates)
      winner = candidates.min_by do |candidate|
        [MACRO_PRIORITY.fetch(candidate.association_macro), candidate.association_name, candidate.relationship_id]
      end
      winner.dup.tap { |relationship| relationship.metadata = merged_relationship_metadata(candidates) }
    end

    def merged_relationship_metadata(candidates)
      return { scoped: true } if candidates.any? { |candidate| candidate.metadata&.fetch(:scoped, false) }

      nil
    end

    def referenced_entity_id(relationship)
      return relationship.target_entity_id if relationship.foreign_key_holder_entity_id == relationship.owner_entity_id

      relationship.owner_entity_id
    end

    def canonical_relationship_id(relationship, holder_id, referenced_id)
      RelationshipIdCodec.direct(
        holder_table: entity_table(holder_id),
        foreign_key_columns: relationship.foreign_key_columns,
        referenced_table: entity_table(referenced_id),
        referenced_key_columns: relationship.referenced_key_columns
      )
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

    def physical_key(holder_id, foreign_key_columns, referenced_id, referenced_key_columns)
      CanonicalJson.dump(
        kind: 'direct',
        holder_entity_id: holder_id,
        foreign_key_columns: foreign_key_columns,
        referenced_entity_id: referenced_id,
        referenced_key_columns: referenced_key_columns
      )
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

    def key_columns(reflection, target_model)
      foreign_key_columns = KeyTuple.normalize(reflection_value(reflection, :foreign_key))
      referenced_key_columns = KeyTuple.normalize(association_primary_key(reflection, target_model))
      return unless KeyTuple.valid_pair?(foreign_key_columns, referenced_key_columns)

      { foreign_key_columns: foreign_key_columns, referenced_key_columns: referenced_key_columns }
    rescue LoadError, SyntaxError, StandardError
      nil
    end

    def direct_key_columns(reflection, owner)
      foreign_key_columns = KeyTuple.normalize(reflection_value(reflection, :foreign_key))
      referenced_value = reflection_value(reflection, :active_record_primary_key)
      referenced_value = owner.primary_key_columns if referenced_value.nil?
      referenced_key_columns = KeyTuple.normalize(referenced_value)
      return unless KeyTuple.valid_pair?(foreign_key_columns, referenced_key_columns)
      if reflection_options(reflection).key?(:primary_key) &&
         !(referenced_key_columns.one? && owner.primary_key_columns.one? &&
           referenced_key_columns == owner.primary_key_columns)
        return :non_primary_key
      end

      { foreign_key_columns: foreign_key_columns, referenced_key_columns: referenced_key_columns }
    rescue LoadError, SyntaxError, StandardError
      nil
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

    def db_foreign_key?(owner, target, foreign_key_columns, referenced_key_columns)
      owner.foreign_keys.any? do |foreign_key|
        foreign_key.from_table == owner.table_name &&
          foreign_key.columns == foreign_key_columns &&
          foreign_key.to_table == target.table_name &&
          foreign_key.primary_key_columns == referenced_key_columns
      end
    end

    def columns_nullable?(entity, column_names)
      nullabilities = column_names.map { |name| entity.columns.find { |column| column.name == name }&.nullable }
      false if nullabilities.all?(false)
    end

    def columns_present?(entity, names) = names.all? { |name| column_names(entity).include?(name) }

    def association_primary_key(reflection, target_model)
      return unless reflection.respond_to?(:association_primary_key)

      return reflection.association_primary_key if reflection.method(:association_primary_key).arity.zero?

      reflection.association_primary_key(target_model)
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

    def safe_value(object, method_name)
      return unless object.respond_to?(method_name)

      object.public_send(method_name)
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

      nil
    rescue LoadError, SyntaxError, StandardError
      'ASSOCIATION_SOURCE_UNRESOLVED'
    end

    def through_physical_key_omission_code(context, owner, reflection)
      current = owner
      through_physical_reflections(reflection).each do |hop|
        target_model, target_constant = resolve_target(hop)
        break unless target_model

        target = context.entity_by_constant[target_constant]
        break unless target

        code = direct_hop_key_omission_code(current, target, target_model, hop)
        return code if code

        current = target
      end
      nil
    rescue LoadError, SyntaxError, StandardError
      'ASSOCIATION_COMPOSITE_KEY_OMITTED'
    end

    def direct_hop_key_omission_code(owner, target, target_model, reflection)
      if reflection_macro(reflection) == :belongs_to
        keys = key_columns(reflection, target_model)
        return 'ASSOCIATION_COMPOSITE_KEY_OMITTED' unless keys
        return 'ASSOCIATION_NON_PRIMARY_KEY_OMITTED' if reflection_options(reflection).key?(:primary_key)

        holder = owner
        referenced = target
      else
        keys = direct_key_columns(reflection, owner)
        return 'ASSOCIATION_COMPOSITE_KEY_OMITTED' unless keys
        return 'ASSOCIATION_NON_PRIMARY_KEY_OMITTED' if keys == :non_primary_key

        holder = target
        referenced = owner
      end
      return if columns_present?(holder, keys.fetch(:foreign_key_columns)) &&
                columns_present?(referenced, keys.fetch(:referenced_key_columns))

      'ASSOCIATION_KEY_COLUMN_MISSING'
    end

    def through_physical_reflections(reflection, seen = {}.compare_by_identity)
      return [] if seen.key?(reflection)

      seen[reflection] = true
      through_reflection = safe_reflection_value(reflection, :through_reflection)
      source_reflection = safe_reflection_value(reflection, :source_reflection)
      [through_reflection, source_reflection].compact.flat_map do |hop|
        through?(hop) ? through_physical_reflections(hop, seen) : [hop]
      end
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
