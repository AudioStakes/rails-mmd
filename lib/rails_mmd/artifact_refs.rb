# frozen_string_literal: true

require 'rails_mmd/redactor'

module RailsMmd
  # Sanitizes and validates diagnostic artifact references.
  class ArtifactRefs
    ALLOWED_KEYS = %w[artifact_kind domain_id path].freeze
    PATH_PATTERN = %r{\A(?!/)(?!.*(?:^|/)\.\.(?:/|$))(?!.*//)[A-Za-z0-9._/-]+\z}

    def initialize(redactor: Redactor.new)
      @redactor = redactor
    end

    def sanitize(artifact_refs)
      artifact_refs.map do |artifact_ref|
        sanitize_ref(artifact_ref)
      end
    end

    private

    attr_reader :redactor

    def sanitize_ref(artifact_ref)
      ref = artifact_ref.to_h.transform_keys(&:to_s)
      unknown_keys = ref.keys - ALLOWED_KEYS
      raise ArgumentError, "unknown artifact ref keys: #{unknown_keys.join(', ')}" unless unknown_keys.empty?

      ref['path'] = safe_path(ref.fetch('path')) if ref.key?('path')
      ref
    end

    def safe_path(path)
      path = redactor.sanitize(path)
      return path if path.match?(PATH_PATTERN)

      raise ArgumentError, "invalid artifact path: #{path}"
    end
  end
end
