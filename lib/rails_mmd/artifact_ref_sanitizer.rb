# frozen_string_literal: true

require 'rails_mmd/redactor'

module RailsMmd
  # Sanitizes and validates diagnostic artifact references.
  class ArtifactRefSanitizer
    ALLOWED_KEYS = %w[artifact_kind domain_id path].freeze
    ARTIFACT_KINDS = %w[diagnostics er class render_plan stderr].freeze
    DOMAIN_ID_PATTERN = /\A[a-z][a-z0-9]*(?:_[a-z0-9]+)*\z/
    PATH_PATTERN = %r{\A(?!/)(?!.*(?:^|/)\.\.(?:/|$))(?!.*//)[A-Za-z0-9._/-]+\z}
    REQUIRED_KEYS = %w[artifact_kind domain_id].freeze

    def initialize(redactor: Redactor.new)
      @redactor = redactor
    end

    def sanitize(artifact_refs)
      artifact_refs.map do |artifact_ref|
        sanitize_reference(artifact_ref)
      end
    end

    private

    attr_reader :redactor

    def sanitize_reference(artifact_ref)
      reference = artifact_ref.to_h.transform_keys(&:to_s)
      unknown_keys = reference.keys - ALLOWED_KEYS
      raise ArgumentError, "unknown artifact ref keys: #{unknown_keys.join(', ')}" unless unknown_keys.empty?

      validate_reference!(reference)
      reference['path'] = safe_path(reference.fetch('path')) if reference.key?('path')
      reference
    end

    def validate_reference!(reference)
      missing_keys = REQUIRED_KEYS - reference.keys
      raise ArgumentError, "missing artifact ref keys: #{missing_keys.join(', ')}" unless missing_keys.empty?
      unless ARTIFACT_KINDS.include?(reference.fetch('artifact_kind'))
        raise ArgumentError,
              "invalid artifact_kind: #{reference.fetch('artifact_kind')}"
      end

      domain_id = reference.fetch('domain_id')
      return if domain_id.nil? || domain_id.match?(DOMAIN_ID_PATTERN)

      raise ArgumentError, "invalid artifact domain_id: #{domain_id}"
    end

    def safe_path(path)
      path = redactor.sanitize(path)
      return path if path.match?(PATH_PATTERN)

      raise ArgumentError, "invalid artifact path: #{path}"
    end
  end
end
