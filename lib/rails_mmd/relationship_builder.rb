# frozen_string_literal: true

require 'rails_mmd/diagnostics'

module RailsMmd
  # Builds selected-domain direct belongs_to relationship records.
  # rubocop:disable Metrics/AbcSize, Metrics/ClassLength, Metrics/CyclomaticComplexity, Metrics/MethodLength, Metrics/PerceivedComplexity
  class RelationshipBuilder
    DomainResult = Struct.new(:domain_id, :relationships, :diagnostics, keyword_init: true)
    Relationship = Struct.new(
      :relationship_id,
      :owner_entity_id,
      :target_entity_id,
      :association_name,
      :owner_foreign_key_column,
      :target_primary_key_column,
      :owner_fk_unique,
      :db_foreign_key,
      :owner_fk_nullable,
      :owner_cardinality,
      :target_cardinality,
      keyword_init: true
    )
    Result = Struct.new(:domains, :diagnostics, keyword_init: true) do
      def success?
        true
      end
    end

    ASSOCIATION_NAME_PATTERN = /\A[a-z][a-z0-9]*(?:_[a-z0-9]+)*[!?=]?\z/
    DomainContext = Struct.new(:domain, keyword_init: false) do
      def domain_id = domain.domain_id

      def entities = domain.entities

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

      context.entities.each do |owner|
        owner_model = resolve_model(owner.ruby_constant)
        next unless owner_model

        belongs_to_reflections(owner_model).each do |reflection|
          relationship, diagnostic = build_reflection(context, owner, reflection)
          relationships << relationship if relationship
          output_diagnostics << diagnostic if diagnostic
        end
      end

      DomainResult.new(
        domain_id: domain.domain_id,
        relationships: relationships.sort_by(&:relationship_id),
        diagnostics: output_diagnostics
      )
    end

    def belongs_to_reflections(model)
      if model.respond_to?(:reflect_on_all_associations)
        Array(model.reflect_on_all_associations(:belongs_to))
      elsif model.respond_to?(:reflections)
        model.reflections.values.select { |reflection| reflection_macro(reflection) == :belongs_to }
      else
        []
      end
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

      Relationship.new(
        relationship_id: "relationships/#{owner.table_name}/#{association_name}",
        owner_entity_id: entity_id(owner),
        target_entity_id: entity_id(target),
        association_name: association_name,
        owner_foreign_key_column: owner_fk,
        target_primary_key_column: target_pk,
        owner_fk_unique: owner_unique,
        db_foreign_key: db_foreign_key,
        owner_fk_nullable: owner_fk_nullable,
        owner_cardinality: owner_unique ? '0..1' : '0..many',
        target_cardinality: db_foreign_key && owner_fk_nullable == false ? '1..1' : '0..1'
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

    def unique_owner_fk?(owner, owner_fk)
      owner.indexes.any? do |index|
        index.unique == true &&
          Array(index.columns) == [owner_fk] &&
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
