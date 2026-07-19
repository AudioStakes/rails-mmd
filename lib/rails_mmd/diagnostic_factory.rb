# frozen_string_literal: true

require 'json'
require 'rails_mmd/artifact_ref_sanitizer'
require 'rails_mmd/canonical_json'
require 'rails_mmd/metadata_shapes'
require 'rails_mmd/redactor'
require 'rails_mmd/subject_ids'

module RailsMmd
  # Schema-backed diagnostic object factory.
  class DiagnosticFactory
    CATALOG_PATH = Pathname(__dir__).join('../../fixtures/schemas/diagnostics/valid/catalog.json').expand_path
    SCHEMA_PATH = Pathname(__dir__).join('../../schemas/diagnostics.schema.json').expand_path
    FREE_TEXT_REFS = %w[#/$defs/relative_path #/$defs/sanitized_string].freeze

    def initialize(redactor: Redactor.new, artifact_refs: ArtifactRefSanitizer.new(redactor: redactor))
      @redactor = redactor
      @artifact_refs = artifact_refs
    end

    def build(code:, message:, **options)
      template = self.class.catalog.fetch(code)
      diagnostic = diagnostic_payload(code, message, template, options)
      validate_metadata_keys!(code, diagnostic.fetch('metadata'))
      self.class.metadata_shapes.validate!(code, diagnostic.fetch('metadata'))
      diagnostic
    end

    def diagnostic_payload(code, message, template, options)
      metadata = options.fetch(:metadata, {})
      content = diagnostic_content(code, message, options, metadata)
      diagnostic_defaults(code, template, options, content).merge(content)
    end

    def diagnostic_defaults(code, template, options, content)
      {
        'diagnostic_id' => diagnostic_id(code, content.fetch('subject_id'), content.fetch('metadata')),
        'code' => code,
        'severity' => options[:severity] || template.fetch('severity'),
        'phase' => template.fetch('phase'),
        'scope' => template.fetch('scope')
      }
    end

    def diagnostic_content(code, message, options, metadata)
      {
        'subject_id' => SubjectIds.normalize(options[:subject_id], code: code),
        'message' => redactor.sanitize(message),
        'metadata' => sanitized_metadata(code, metadata),
        'artifact_refs' => artifact_refs.sanitize(options.fetch(:artifact_refs, [])),
        'remediation' => options[:remediation] && redactor.sanitize_object(options[:remediation])
      }
    end

    def exception_metadata(exception)
      {
        'exception_class' => exception.class.name,
        'exception_summary' => redactor.sanitize(exception.message),
        'backtrace' => nil
      }
    end

    def self.codes
      catalog.keys
    end

    def self.catalog
      @catalog ||= JSON.parse(CATALOG_PATH.read).fetch('diagnostics').to_h do |diagnostic|
        [diagnostic.fetch('code'), diagnostic]
      end
    end

    def self.metadata_shapes
      @metadata_shapes ||= MetadataShapes.new(schema_path: SCHEMA_PATH)
    end

    private

    attr_reader :artifact_refs, :redactor

    def diagnostic_id(code, subject_id, metadata)
      digest = CanonicalJson.digest_sha256('code' => code, 'subject_id' => subject_id, 'metadata' => metadata)
      "diag_#{digest[0, 16]}"
    end

    def sanitized_metadata(code, metadata)
      shape = self.class.metadata_shapes.fetch(code)
      template_keys = shape.fetch('properties').keys
      metadata = stringify_keys(metadata)
      raise ArgumentError, "unknown diagnostic metadata for #{code}" unless (metadata.keys - template_keys).empty?

      metadata.transform_values.with_index do |value, index|
        sanitize_metadata_value(metadata.keys.fetch(index), value)
      end
    end

    def sanitize_metadata_value(key, value)
      return value unless metadata_free_text?(key)
      raise ArgumentError, "invalid diagnostic metadata value for #{key}" unless value.is_a?(String)

      redactor.sanitize(value)
    end

    def metadata_free_text?(key)
      FREE_TEXT_REFS.include?(self.class.metadata_shapes.properties.fetch(key).fetch('$ref', nil))
    end

    def validate_metadata_keys!(code, metadata)
      required_keys = self.class.metadata_shapes.fetch(code).fetch('required')
      missing_keys = required_keys - metadata.keys
      return if missing_keys.empty?

      raise ArgumentError,
            "missing diagnostic metadata for #{code}: #{missing_keys.join(', ')}"
    end

    def stringify_keys(value)
      value.to_h.transform_keys(&:to_s)
    end
  end
end
