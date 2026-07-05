# frozen_string_literal: true

require 'json'
require 'rails_mmd/canonical_json'
require 'rails_mmd/redactor'

module RailsMmd
  # Schema-backed diagnostic object factory.
  class Diagnostics
    CATALOG_PATH = Pathname(__dir__).join('../../fixtures/schemas/diagnostics/valid/catalog.json').expand_path

    def initialize(redactor: Redactor.new)
      @redactor = redactor
    end

    def build(code:, message:, **options)
      template = self.class.catalog.fetch(code)
      diagnostic = diagnostic_payload(code, message, template, options)
      validate_metadata_keys!(code, diagnostic.fetch('metadata'))
      diagnostic
    end

    def diagnostic_payload(code, message, template, options)
      metadata = options.fetch(:metadata, {})
      diagnostic_defaults(code, template, options, metadata).merge(
        diagnostic_content(code, message, options, metadata)
      )
    end

    def diagnostic_defaults(code, template, options, metadata)
      {
        'diagnostic_id' => diagnostic_id(code, options[:subject_id], metadata),
        'code' => code,
        'severity' => diagnostic_severity(template, options),
        'phase' => diagnostic_phase(template),
        'scope' => diagnostic_scope(template)
      }
    end

    def diagnostic_content(code, message, options, metadata)
      {
        'subject_id' => options[:subject_id] && redactor.sanitize(options[:subject_id]),
        'message' => redactor.sanitize(message),
        'metadata' => sanitized_metadata(code, metadata),
        'artifact_refs' => diagnostic_artifact_refs(options),
        'remediation' => diagnostic_remediation(options)
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

    attr_reader :redactor

    def diagnostic_id(code, subject_id, metadata)
      digest = CanonicalJson.digest_sha256('code' => code, 'subject_id' => subject_id, 'metadata' => metadata)
      "diag_#{digest[0, 16]}"
    end

    def diagnostic_severity(template, options)
      options[:severity] || template.fetch('severity')
    end

    def diagnostic_phase(template)
      template.fetch('phase')
    end

    def diagnostic_scope(template)
      template.fetch('scope')
    end

    def diagnostic_artifact_refs(options)
      options.fetch(:artifact_refs, [])
    end

    def diagnostic_remediation(options)
      options[:remediation] && redactor.sanitize_object(options[:remediation])
    end

    def sanitized_metadata(code, metadata)
      template_keys = self.class.catalog.fetch(code).fetch('metadata').keys
      metadata = stringify_keys(metadata)
      raise ArgumentError, "unknown diagnostic metadata for #{code}" unless (metadata.keys - template_keys).empty?

      redactor.sanitize_object(metadata)
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
