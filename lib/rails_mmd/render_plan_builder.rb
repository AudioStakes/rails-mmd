# frozen_string_literal: true

require 'rails_mmd/attribute_types'
require 'rails_mmd/canonical_json'
require 'rails_mmd/redactor'
require 'rails_mmd/safe_tokens'

module RailsMmd
  # Projects normalized IR into renderer-only ER or class render plans.
  # rubocop:disable Metrics/AbcSize, Metrics/ClassLength, Metrics/CyclomaticComplexity, Metrics/MethodLength, Metrics/ParameterLists, Naming/MethodParameterName, Style/MultilineBlockChain
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
    FREE_TEXT_SECRET_KEY = /
      (?:
        password|passwd|secret|credential|token|pid|
        api\s*[_-]?\s*key|
        database\s*[_-]?\s*url|
        (?:access|auth|refresh)\s*[_-]?\s*token|
        generated\s*[_-]?\s*at|
        process\s*[_-]?\s*id|
        random\s*[_-]?\s*seed|
        raw\s*[_-]?\s*exception\s*[_-]?\s*backtrace
      )
    /ix
    FREE_TEXT_FORBIDDEN_ASSIGNMENT = /[A-Za-z0-9_-]*#{FREE_TEXT_SECRET_KEY}[A-Za-z0-9_-]*\s*(?::|=|\s+)\s*\S+/ix
    REDACTED_KEY_ASSIGNMENT = /[A-Za-z0-9_-]*\[REDACTED_KEY\][A-Za-z0-9_-]*\s*(?::|=|\s+)\s*\S+/
    URL_PATTERN = %r{\b[a-z][a-z0-9+.-]*://[^\s]+}i
    URL_PLACEHOLDER_PREFIX = "\uE000RAILSMMDURL"
    REDACTED_URL = '[REDACTED_URL]'
    MERMAID_CONTROL_TEXT = /[\r\n\t[:cntrl:]]+/
    CONTROL_SPLIT_ABSOLUTE_PATH =
      /(?<![A-Za-z0-9_])\/[^[:cntrl:]\s)\]}>;,:!?]+(?:[\r\n\t[:cntrl:]][^[:cntrl:]\s)\]}>;,:!?]*)*/
    RUBY_CONSTANT_PATTERN = /\A[A-Z][A-Za-z0-9_]*(?:::[A-Z][A-Za-z0-9_]*)*\z/
    RUBY_CONSTANT_LABEL_PATTERN = /\A[A-Z][A-Za-z0-9_]*\z/
    SNAKE_IDENTIFIER_PATTERN = /\A[a-z][a-z0-9_]*\z/
    ASSOCIATION_LABEL_SUFFIX = /[?!=]\z/
    STRUCTURED_FALLBACK_LABEL = 'X'

    def initialize(safe_tokens: SafeTokens.new, redactor: Redactor.new)
      @safe_tokens = safe_tokens
      @redactor = redactor
    end

    def build(ir:, artifact_kind:, direction:, attributes: :keys, comments: [], available_diagnostic_ids: [])
      entities = filtered_entities(ir, artifact_kind)
      token_sets, diagnostics = token_sets_for(entities, ir.fetch('relationships'), artifact_kind, comments,
                                               ir.fetch('domain_id'))
      payload = payload_for(
        ir: ir,
        entities: entities,
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

    def payload_for(
      ir:, entities:, artifact_kind:, direction:, attributes:, comments:, token_sets:, available_diagnostic_ids:
    )
      ensure_unique_ids!(entities.map { |entity| entity.fetch('entity_id') }, 'render entity_id')
      ensure_unique_ids!(ir.fetch('relationships').map { |relationship| relationship.fetch('relationship_id') },
                         'render relationship_id')
      inheritances = inheritances_payload(entities, artifact_kind, token_sets)
      payload = {
        'schema_version' => 4,
        'artifact_kind' => artifact_kind,
        'domain_id' => ir.fetch('domain_id'),
        'direction' => direction,
        'entities' => entities_payload(entities, attributes, token_sets),
        'inheritances' => inheritances,
        'relationships' => relationships_payload(ir, token_sets),
        'comments' => comments_payload(comments, token_sets),
        'diagnostic_ids' => diagnostic_ids(ir, available_diagnostic_ids),
        'digest_sha256' => nil
      }
      payload.merge('digest_sha256' => CanonicalJson.digest_sha256(payload))
    end

    def token_sets_for(entities, relationships, artifact_kind, comments, domain_id)
      token_sets = {}
      diagnostics = []
      token_subjects(entities, relationships, comments).each do |token_kind, subjects|
        assignment = safe_tokens.assign(
          subjects,
          scope: { artifact_kind: artifact_kind, domain_id: domain_id, token_kind: token_kind }
        )
        token_sets[token_kind] = assignment.fetch(:tokens)
        diagnostics.concat(assignment.fetch(:diagnostics))
      end
      [token_sets, diagnostics]
    end

    def token_subjects(entities, relationships, comments)
      {
        'entity' => entities.map do |entity|
          subject(entity.fetch('entity_id'), structured_mermaid_text(entity.fetch('ruby_constant'), :ruby_constant))
        end,
        'attribute' => entities.flat_map { |entity| attribute_subjects(entity) },
        'relationship' => relationships.map do |relationship|
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

    def entities_payload(entities, attributes, token_sets)
      entities.map do |entity|
        {
          'entity_id' => entity.fetch('entity_id'),
          'entity_kind' => entity_kind(entity),
          'safe_token' => token_sets.fetch('entity').fetch(entity.fetch('entity_id')),
          'label' => entity_label(entity),
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
      end.sort_by do |attribute|
        [attribute.fetch('key_marker').start_with?('PK') ? 0 : 1, attribute.fetch('attribute_id')]
      end
    end

    def relationships_payload(ir, token_sets)
      ir.fetch('relationships').map do |relationship|
        relationship_payload(relationship, token_sets)
      end.sort_by { |relationship| relationship.fetch('relationship_id') }
    end

    def relationship_payload(relationship, token_sets)
      er_left, = ER_MARKERS.fetch(relationship.fetch('owner_cardinality'))
      _, er_right = ER_MARKERS.fetch(relationship.fetch('target_cardinality'))
      payload = {
        'relationship_id' => relationship.fetch('relationship_id'),
        'safe_token' => token_sets.fetch('relationship').fetch(relationship.fetch('relationship_id')),
        'owner_safe_token' => safe_token_for_entity(token_sets, relationship.fetch('owner_entity_id')),
        'target_safe_token' => safe_token_for_entity(token_sets, relationship.fetch('target_entity_id')),
        'label' => relationship_label(relationship),
        'owner_cardinality' => relationship.fetch('owner_cardinality'),
        'target_cardinality' => relationship.fetch('target_cardinality'),
        'er_left_marker' => er_left,
        'er_right_marker' => er_right,
        'class_owner_multiplicity' => CLASS_MULTIPLICITIES.fetch(relationship.fetch('owner_cardinality')),
        'class_target_multiplicity' => CLASS_MULTIPLICITIES.fetch(relationship.fetch('target_cardinality'))
      }
      payload['metadata'] = { 'scoped' => true } if relationship.dig('metadata', 'scoped') == true
      payload
    end

    def inheritances_payload(entities, artifact_kind, token_sets)
      return [] if artifact_kind == 'er'

      entities_by_id = entities.to_h { |entity| [entity.fetch('entity_id'), entity] }
      payloads = entities.filter_map do |entity|
        next unless entity_kind(entity) == 'sti_subtype'

        parent_entity_id = entity.fetch('metadata').fetch('parent_entity_id')
        unless entities_by_id.key?(parent_entity_id)
          raise ArgumentError, "inheritance parent missing: #{entity.fetch('entity_id')}"
        end

        {
          'inheritance_id' => "inheritances/#{entity.fetch('entity_id')}",
          'parent_entity_id' => parent_entity_id,
          'child_entity_id' => entity.fetch('entity_id'),
          'parent_safe_token' => safe_token_for_entity(token_sets, parent_entity_id),
          'child_safe_token' => safe_token_for_entity(token_sets, entity.fetch('entity_id'))
        }
      end
      ensure_unique_ids!(payloads.map { |inheritance| inheritance.fetch('inheritance_id') }, 'render inheritance_id')
      payloads.sort_by { |inheritance| inheritance.fetch('inheritance_id') }
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

    def entity_label(entity)
      if entity_kind(entity) == 'sti_subtype'
        structured_mermaid_text(entity.fetch('ruby_constant'), :ruby_constant)
      else
        structured_mermaid_text(entity.fetch('ruby_constant').split('::').last, :ruby_constant_label)
      end
    end

    def entity_kind(entity)
      entity.dig('metadata', 'kind') == 'sti_subtype' ? 'sti_subtype' : 'physical'
    end

    def filtered_entities(ir, artifact_kind)
      entities = ir.fetch('entities')
      return entities if artifact_kind == 'class'

      entities.reject { |entity| entity_kind(entity) == 'sti_subtype' }
    end

    def free_text_mermaid_text(value)
      urls = []
      text = protect_urls(value.to_s.delete("\u0000"), urls)
      text = text.gsub(CONTROL_SPLIT_ABSOLUTE_PATH, '[REDACTED_PATH]')
      text = text.gsub(MERMAID_CONTROL_TEXT, ' ')
      text = text.gsub(FREE_TEXT_FORBIDDEN_ASSIGNMENT, '[REDACTED]')
      text = redactor.sanitize(text).gsub(REDACTED_KEY_ASSIGNMENT, '[REDACTED]')
      restore_urls(text, urls).gsub(/\s+/, ' ').strip
    end

    def structured_mermaid_text(value, grammar)
      text = single_line_text(value)
      return STRUCTURED_FALLBACK_LABEL unless structured_pattern(grammar).match?(text)

      text
    end

    def single_line_text(value)
      value.to_s.delete("\u0000").gsub(MERMAID_CONTROL_TEXT, ' ').gsub(/\s+/, ' ').strip
    end

    def structured_pattern(grammar)
      {
        ruby_constant: RUBY_CONSTANT_PATTERN,
        ruby_constant_label: RUBY_CONSTANT_LABEL_PATTERN,
        snake_identifier: SNAKE_IDENTIFIER_PATTERN
      }.fetch(grammar)
    end

    def protect_urls(text, urls)
      text.gsub(URL_PATTERN) do |_url|
        urls << REDACTED_URL
        "#{URL_PLACEHOLDER_PREFIX}#{urls.length - 1}"
      end
    end

    def restore_urls(text, urls)
      urls.each_with_index.reduce(text) do |output, (url, index)|
        output.gsub("#{URL_PLACEHOLDER_PREFIX}#{index}", url)
      end
    end

    def diagnostic_ids(ir, available_diagnostic_ids)
      allowed = available_diagnostic_ids.map(&:to_s)
      ir.fetch('diagnostic_ids').select { |diagnostic_id| allowed.include?(diagnostic_id) }.sort
    end

    def key_marker(role)
      {
        'primary_key' => 'PK',
        'foreign_key' => 'FK',
        'primary_foreign_key' => 'PK, FK'
      }.fetch(role)
    end

    def safe_token_for_entity(token_sets, entity_id)
      token_sets.fetch('entity').fetch(entity_id)
    rescue KeyError
      raise ArgumentError, "render entity token missing: #{entity_id}"
    end

    def ensure_unique_ids!(ids, label)
      duplicate_id = ids.group_by(&:itself).find { |_id, group| group.length > 1 }&.first
      return unless duplicate_id

      raise ArgumentError, "duplicate #{label}: #{duplicate_id}"
    end
  end
  # rubocop:enable Metrics/AbcSize, Metrics/ClassLength, Metrics/CyclomaticComplexity, Metrics/MethodLength, Metrics/ParameterLists, Naming/MethodParameterName, Style/MultilineBlockChain
end
