# frozen_string_literal: true

require 'json'
require 'rails_mmd/artifact_refs'
require 'rails_mmd/canonical_json'
require 'rails_mmd/redactor'
require 'rails_mmd/subject_ids'

module RailsMmd
  # Schema-backed diagnostic object factory.
  class Diagnostics
    CATALOG_PATH = Pathname(__dir__).join('../../fixtures/schemas/diagnostics/valid/catalog.json').expand_path

    def initialize(redactor: Redactor.new, artifact_refs: ArtifactRefs.new(redactor: redactor))
      @redactor = redactor
      @artifact_refs = artifact_refs
    end

    def build(code:, message:, **options)
      template = self.class.catalog.fetch(code)
      diagnostic = diagnostic_payload(code, message, template, options)
      validate_metadata_keys!(code, diagnostic.fetch('metadata'))
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

    private

    attr_reader :artifact_refs, :redactor

    def diagnostic_id(code, subject_id, metadata)
      digest = CanonicalJson.digest_sha256('code' => code, 'subject_id' => subject_id, 'metadata' => metadata)
      "diag_#{digest[0, 16]}"
    end

    def sanitized_metadata(code, metadata)
      template_keys = self.class.catalog.fetch(code).fetch('metadata').keys
      metadata = stringify_keys(metadata)
      raise ArgumentError, "unknown diagnostic metadata for #{code}" unless (metadata.keys - template_keys).empty?

      metadata.transform_values.with_index do |value, index|
        sanitize_metadata_value(metadata.keys.fetch(index), value)
      end
    end

    def sanitize_metadata_value(key, value)
      case key
      when 'config_path', 'path', 'exception_summary', 'reason'
        sanitize_metadata_free_text(value)
      else
        value
      end
    end

    def sanitize_metadata_free_text(value)
      case value
      when String
        redactor.sanitize(value)
      when Array
        value.map { |item| sanitize_metadata_free_text(item) }
      else
        value
      end
    end

    def validate_metadata_keys!(code, metadata)
      required_keys = self.class.catalog.fetch(code).fetch('metadata').keys
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
