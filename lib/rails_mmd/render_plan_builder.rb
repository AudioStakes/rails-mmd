# frozen_string_literal: true

require 'rails_mmd/attribute_types'
require 'rails_mmd/canonical_json'
require 'rails_mmd/redactor'
require 'rails_mmd/safe_token_assigner'

module RailsMmd
  # Projects normalized IR into renderer-only ER or class render plans.
  # rubocop:disable Metrics/AbcSize, Metrics/ClassLength, Metrics/MethodLength, Metrics/ParameterLists, Naming/MethodParameterName, Style/MultilineBlockChain
  class RenderPlanBuilder
    DomainResult = Struct.new(:domain_id, :payload, :diagnostics, keyword_init: true)

    ER_MARKERS = {
      '0..1' => ['|o', 'o|'],
      '1..1' => ['||', '||'],
      '0..many' => ['}o', 'o{'],
      '1..many' => ['}|', '|{']
    }.freeze
    CLASS_MULTIPLICITIES = {
      '0..1' => '0..1',
      '1..1' => '1',
      '0..many' => '0..*',
      '1..many' => '1..*'
    }.freeze
    ASSOCIATION_LABEL_SUFFIX = /[?!=]\z/

    def initialize(safe_tokens: SafeTokenAssigner.new, redactor: Redactor.new)
      @safe_tokens = safe_tokens
      @redactor = redactor
    end

    def build(ir:, artifact_kind:, direction:, attributes: :keys, comments: [], available_diagnostic_ids: [])
      token_sets, diagnostics = token_sets_for(ir, artifact_kind, comments)
      payload = payload_for(
        ir: ir,
        artifact_kind: artifact_kind,
        direction: direction,
        attributes: attributes.to_sym,
        comments: comments,
        token_sets: token_sets,
        available_diagnostic_ids: available_diagnostic_ids
      )

      DomainResult.new(domain_id: ir.fetch('domain_id'), payload: payload, diagnostics: diagnostics)
    end

    private

    attr_reader :redactor, :safe_tokens

    def payload_for(ir:, artifact_kind:, direction:, attributes:, comments:, token_sets:, available_diagnostic_ids:)
      payload = {
        'schema_version' => 1,
        'artifact_kind' => artifact_kind,
        'domain_id' => ir.fetch('domain_id'),
        'direction' => direction,
        'entities' => entities_payload(ir, attributes, token_sets),
        'relationships' => relationships_payload(ir, token_sets),
        'comments' => comments_payload(comments, token_sets),
        'diagnostic_ids' => diagnostic_ids(ir, available_diagnostic_ids),
        'digest_sha256' => nil
      }
      payload.merge('digest_sha256' => CanonicalJson.digest_sha256(payload))
    end

    def token_sets_for(ir, artifact_kind, comments)
      token_sets = {}
      diagnostics = []
      token_subjects(ir, comments).each do |token_kind, subjects|
        assignment = safe_tokens.assign(
          subjects,
          scope: { artifact_kind: artifact_kind, domain_id: ir.fetch('domain_id'), token_kind: token_kind }
        )
        token_sets[token_kind] = assignment.fetch(:tokens)
        diagnostics.concat(assignment.fetch(:diagnostics))
      end
      [token_sets, diagnostics]
    end

    def token_subjects(ir, comments)
      {
        'entity' => ir.fetch('entities').map do |entity|
          subject(entity.fetch('entity_id'), structured_mermaid_text(entity.fetch('ruby_constant'), :ruby_constant))
        end,
        'attribute' => ir.fetch('entities').flat_map { |entity| attribute_subjects(entity) },
        'relationship' => ir.fetch('relationships').map do |relationship|
          subject(relationship.fetch('relationship_id'),
                  relationship_label(relationship))
        end,
        'comment' => comments.map { |comment| subject(comment.fetch('comment_id'), comment.fetch('comment_id')) }
      }
    end

    def subject(identity, source)
      { identity: identity, source: source }
    end

    def attribute_subjects(entity)
      entity.fetch('attributes').map do |attribute|
        subject(attribute.fetch('attribute_id'), structured_mermaid_text(attribute.fetch('name'), :snake_identifier))
      end
    end

    def entities_payload(ir, attributes, token_sets)
      ir.fetch('entities').map do |entity|
        {
          'entity_id' => entity.fetch('entity_id'),
          'safe_token' => token_sets.fetch('entity').fetch(entity.fetch('entity_id')),
          'label' => structured_mermaid_text(entity.fetch('ruby_constant').split('::').last, :ruby_constant_label),
          'attributes' => attributes == :none ? [] : attributes_payload(entity, token_sets)
        }
      end.sort_by { |entity| entity.fetch('entity_id') }
    end

    def attributes_payload(entity, token_sets)
      entity.fetch('attributes').map do |attribute|
        {
          'attribute_id' => attribute.fetch('attribute_id'),
          'safe_token' => token_sets.fetch('attribute').fetch(attribute.fetch('attribute_id')),
          'label' => sanitize_attribute_name(attribute.fetch('name')),
          'type' => AttributeTypes.normalize(attribute['type']),
          'key_marker' => key_marker(attribute.fetch('role'))
        }
      end.sort_by { |attribute| [attribute.fetch('key_marker') == 'PK' ? 0 : 1, attribute.fetch('attribute_id')] }
    end

    def relationships_payload(ir, token_sets)
      ir.fetch('relationships').map do |relationship|
        relationship_payload(relationship, token_sets)
      end.sort_by { |relationship| relationship.fetch('relationship_id') }
    end

    def relationship_payload(relationship, token_sets)
      er_left, = ER_MARKERS.fetch(relationship.fetch('owner_cardinality'))
      _, er_right = ER_MARKERS.fetch(relationship.fetch('target_cardinality'))
      {
        'relationship_id' => relationship.fetch('relationship_id'),
        'safe_token' => token_sets.fetch('relationship').fetch(relationship.fetch('relationship_id')),
        'owner_safe_token' => token_sets.fetch('entity').fetch(relationship.fetch('owner_entity_id')),
        'target_safe_token' => token_sets.fetch('entity').fetch(relationship.fetch('target_entity_id')),
        'label' => relationship_label(relationship),
        'owner_cardinality' => relationship.fetch('owner_cardinality'),
        'target_cardinality' => relationship.fetch('target_cardinality'),
        'er_left_marker' => er_left,
        'er_right_marker' => er_right,
        'class_owner_multiplicity' => CLASS_MULTIPLICITIES.fetch(relationship.fetch('owner_cardinality')),
        'class_target_multiplicity' => CLASS_MULTIPLICITIES.fetch(relationship.fetch('target_cardinality'))
      }
    end

    def comments_payload(comments, token_sets)
      comments.map do |comment|
        {
          'comment_id' => comment.fetch('comment_id'),
          'safe_token' => token_sets.fetch('comment').fetch(comment.fetch('comment_id')),
          'text' => sanitize_comment(comment.fetch('text'))
        }
      end.sort_by { |comment| comment.fetch('comment_id') }
    end

    def sanitize_comment(text)
      free_text_mermaid_text(text)
    end

    def sanitize_attribute_name(name)
      structured_mermaid_text(name, :snake_identifier)
    end

    def relationship_label(relationship)
      structured_mermaid_text(relationship.fetch('association_name').to_s.sub(ASSOCIATION_LABEL_SUFFIX, ''),
                              :snake_identifier)
    end

    def free_text_mermaid_text(value)
      Redactor.sanitize_mermaid_free_text(value, sanitizer: redactor)
    end

    def structured_mermaid_text(value, grammar)
      Redactor.sanitize_mermaid_structured(value, grammar: grammar)
    end

    def diagnostic_ids(ir, available_diagnostic_ids)
      allowed = available_diagnostic_ids.map(&:to_s)
      ir.fetch('diagnostic_ids').select { |diagnostic_id| allowed.include?(diagnostic_id) }.sort
    end

    def key_marker(role)
      { 'primary_key' => 'PK', 'foreign_key' => 'FK' }.fetch(role)
    end
  end
  # rubocop:enable Metrics/AbcSize, Metrics/ClassLength, Metrics/MethodLength, Metrics/ParameterLists, Naming/MethodParameterName, Style/MultilineBlockChain
end
