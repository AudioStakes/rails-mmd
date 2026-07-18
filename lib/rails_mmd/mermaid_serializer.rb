# frozen_string_literal: true

require 'rails_mmd/diagnostics'
require 'rails_mmd/schema_validator'

module RailsMmd
  # Serializes renderer-only plans into deterministic P0 Mermaid text.
  # rubocop:disable Metrics/ClassLength
  class MermaidSerializer
    Result = Struct.new(:text, :diagnostics, keyword_init: true)

    DOMAIN_ID_PATTERN = /\A[a-z][a-z0-9]*(?:_[a-z0-9]+)*\z/
    ARTIFACT_KINDS = %w[er class].freeze

    def initialize(diagnostics: Diagnostics.new, schema_validator: SchemaValidator.new)
      @diagnostics = diagnostics
      @schema_validator = schema_validator
    end

    def serialize(render_plan:)
      ensure_valid_render_plan!(render_plan)
      Result.new(text: text_for(render_plan), diagnostics: [])
    rescue StandardError => e
      Result.new(text: nil, diagnostics: [serialization_diagnostic(render_plan, e)])
    end

    private

    attr_reader :diagnostics, :schema_validator

    def ensure_valid_render_plan!(render_plan)
      return if schema_validator.valid?(:render_plan, render_plan)

      raise ArgumentError, 'render plan schema invalid'
    end

    def text_for(render_plan)
      return er_text(render_plan) if render_plan.fetch('artifact_kind') == 'er'

      class_text(render_plan)
    end

    def er_text(render_plan)
      lines = header_lines('erDiagram', render_plan) + comment_lines(render_plan)
      lines.concat(er_body_lines(render_plan))
      "#{lines.join("\n")}\n"
    end

    def er_body_lines(render_plan)
      if render_plan.fetch('entities').any? { |entity| entity.fetch('attributes').any? }
        return er_relationship_lines(render_plan) +
               render_plan.fetch('entities').flat_map { |entity| er_entity_lines(entity) }
      end

      render_plan.fetch('entities').map { |entity| "  #{entity.fetch('safe_token')}" } +
        er_relationship_lines(render_plan)
    end

    def class_text(render_plan)
      lines = header_lines('classDiagram', render_plan) + comment_lines(render_plan)
      lines.concat(render_plan.fetch('entities').flat_map { |entity| class_entity_lines(entity) })
      lines.concat(class_inheritance_lines(render_plan))
      lines.concat(class_relationship_lines(render_plan))
      "#{lines.join("\n")}\n"
    end

    def header_lines(diagram, render_plan)
      [
        diagram,
        "  direction #{render_plan.fetch('direction')}"
      ]
    end

    def comment_lines(render_plan)
      render_plan.fetch('comments').map { |comment| "  %% #{line_text(comment.fetch('text'), field: 'comment text')}" }
    end

    def er_relationship_lines(render_plan)
      render_plan.fetch('relationships').map do |relationship|
        "  #{relationship.fetch('owner_safe_token')} #{relationship.fetch('er_left_marker')}.." \
          "#{relationship.fetch('er_right_marker')} #{relationship.fetch('target_safe_token')} : " \
          "#{non_empty_label(relationship)}"
      end
    end

    def class_relationship_lines(render_plan)
      render_plan.fetch('relationships').map do |relationship|
        "  #{relationship.fetch('owner_safe_token')} \"#{relationship.fetch('class_owner_multiplicity')}\" " \
          "--> \"#{relationship.fetch('class_target_multiplicity')}\" " \
          "#{relationship.fetch('target_safe_token')} : #{non_empty_label(relationship)}"
      end
    end

    def class_inheritance_lines(render_plan)
      render_plan.fetch('inheritances').map do |inheritance|
        "  #{inheritance.fetch('parent_safe_token')} <|-- #{inheritance.fetch('child_safe_token')}"
      end
    end

    def er_entity_lines(entity)
      return ["  #{entity.fetch('safe_token')}"] if entity.fetch('attributes').empty?

      [
        "  #{entity.fetch('safe_token')} {",
        *entity.fetch('attributes').map { |attribute| "    #{er_attribute_line(attribute)}" },
        '  }'
      ]
    end

    def class_entity_lines(entity)
      declaration = class_declaration(entity)
      return ["  #{declaration}"] if entity.fetch('attributes').empty?

      [
        "  #{declaration} {",
        *entity.fetch('attributes').map { |attribute| "    #{class_attribute_line(attribute)}" },
        '  }'
      ]
    end

    def class_declaration(entity)
      declaration = "class #{entity.fetch('safe_token')}"
      return declaration unless entity.fetch('entity_kind') == 'sti_subtype'

      "#{declaration}[\"#{line_text(entity.fetch('label'), field: 'entity label')}\"]"
    end

    def er_attribute_line(attribute)
      [
        attribute.fetch('type'),
        line_text(attribute.fetch('label'), field: 'attribute label'),
        attribute['key_marker']
      ].compact.join(' ')
    end

    def class_attribute_line(attribute)
      "+#{attribute.fetch('type')} #{line_text(attribute.fetch('label'), field: 'attribute label')}"
    end

    def non_empty_label(relationship)
      label = line_text(relationship.fetch('label'), field: 'relationship label')
      raise ArgumentError, 'relationship label is required' if label.empty?

      label
    end

    def line_text(value, field:)
      text = value.to_s
      raise ArgumentError, "#{field} must be single-line" if text.match?(/[\r\n]/)

      text
    end

    def serialization_diagnostic(render_plan, exception)
      diagnostics.build(
        code: 'MERMAID_SERIALIZATION_FAILED',
        message: 'serialization failed',
        subject_id: "#{safe_domain_id(render_plan)}:#{safe_artifact_kind(render_plan)}",
        metadata: serialization_metadata(render_plan, exception)
      )
    end

    def serialization_metadata(render_plan, exception)
      {
        artifact_kind: safe_artifact_kind(render_plan),
        domain_id: safe_domain_id(render_plan),
        reason: exception.message
      }
    end

    def safe_artifact_kind(render_plan)
      return 'er' unless render_plan.is_a?(Hash)

      artifact_kind = render_plan.fetch('artifact_kind', 'er').to_s
      return artifact_kind if ARTIFACT_KINDS.include?(artifact_kind)

      'er'
    end

    def safe_domain_id(render_plan)
      return 'global' unless render_plan.is_a?(Hash)

      domain_id = render_plan.fetch('domain_id', 'global').to_s
      return domain_id if domain_id.match?(DOMAIN_ID_PATTERN)

      'global'
    end
  end
  # rubocop:enable Metrics/ClassLength
end
