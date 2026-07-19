# frozen_string_literal: true

require 'rails_mmd/canonical_json'
require 'rails_mmd/diagnostic_factory'

module RailsMmd
  # Mermaid-safe token generation and scoped collision resolution.
  # @api private
  class SafeTokenAssigner
    TOKEN_KINDS = %w[entity attribute relationship diagnostic comment].freeze
    ARTIFACT_KINDS = %w[er class].freeze

    def initialize(diagnostics: DiagnosticFactory.new)
      @diagnostic_factory = diagnostics
    end

    def assign(subjects, scope:)
      validate_scope!(scope)
      subjects_by_base_token = subjects.group_by { |subject| base_token(subject.fetch(:source)) }
      tokens_by_identity = {}
      collision_diagnostics = assign_token_groups(subjects_by_base_token, scope, tokens_by_identity)

      { tokens: tokens_by_identity, diagnostics: collision_diagnostics }
    end

    private

    attr_reader :diagnostic_factory

    def base_token(source)
      token = source.to_s.unicode_normalize(:nfkd)
      token = token.gsub('::', '_')
      token = token.gsub(/([a-z\d])([A-Z])/, '\\1_\\2')
      token = token.gsub(/([A-Z]+)([A-Z][a-z])/, '\\1_\\2')
      token = token.gsub(/[^A-Za-z0-9]+/, '_')
      token = token.delete('^A-Za-z0-9_')
      token = token.squeeze('_').gsub(/\A_+|_+\z/, '').upcase
      token = 'X' if token.empty?
      token.match?(/\A\d/) ? "X_#{token}" : token
    end

    def validate_scope!(scope)
      raise ArgumentError, 'invalid artifact_kind' unless ARTIFACT_KINDS.include?(scope.fetch(:artifact_kind))
      raise ArgumentError, 'invalid token_kind' unless TOKEN_KINDS.include?(scope.fetch(:token_kind))
    end

    def assign_token_groups(subjects_by_base_token, scope, tokens_by_identity)
      subjects_by_base_token.filter_map do |base_token, colliding_subjects|
        if colliding_subjects.one?
          tokens_by_identity[colliding_subjects.first.fetch(:identity)] = base_token
          next
        end

        resolved_candidates = unique_collision_candidates(scope, base_token, colliding_subjects)
        collision_resolved = !resolved_candidates.nil?
        tokens_by_identity.merge!(resolved_candidates) if collision_resolved
        collision_diagnostic(scope, base_token, colliding_subjects, resolved: collision_resolved)
      end
    end

    def unique_collision_candidates(scope, base_token, colliding_subjects)
      suffix_length = 12
      loop do
        candidates = collision_candidates(scope, base_token, colliding_subjects, suffix_length)
        return candidates if candidates.values.uniq.length == candidates.length

        suffix_length += 4
        break if suffix_length > 64
      end

      nil
    end

    def collision_candidates(scope, base_token, colliding_subjects, suffix_length)
      colliding_subjects.to_h do |subject|
        [
          subject.fetch(:identity),
          "#{base_token}_H#{collision_digest(scope, base_token, subject)[0, suffix_length]}"
        ]
      end
    end

    def collision_digest(scope, base_token, subject)
      payload = {
        'scope' => {
          'artifact_kind' => scope.fetch(:artifact_kind),
          'domain_id' => scope.fetch(:domain_id),
          'token_kind' => scope.fetch(:token_kind)
        },
        'subject_identity' => subject.fetch(:identity),
        'base_safe_token' => base_token
      }
      CanonicalJson.digest_sha256(payload).upcase
    end

    def collision_diagnostic(scope, base_token, colliding_subjects, resolved:)
      diagnostic_factory.build(
        code: 'SAFE_TOKEN_COLLISION',
        subject_id: collision_subject_id(scope, base_token),
        message: collision_message(base_token, resolved),
        severity: resolved ? 'warning' : 'fatal',
        metadata: collision_metadata(scope, base_token, colliding_subjects, resolved: resolved)
      )
    end

    def collision_subject_id(scope, base_token)
      "#{scope.fetch(:artifact_kind)}:#{scope.fetch(:domain_id)}:#{scope.fetch(:token_kind)}:#{base_token}"
    end

    def collision_metadata(scope, base_token, colliding_subjects, resolved:)
      {
        artifact_kind: scope.fetch(:artifact_kind),
        domain_id: scope.fetch(:domain_id),
        token_kind: scope.fetch(:token_kind),
        base_safe_token: base_token,
        collision_subject_count: colliding_subjects.length,
        resolved: resolved
      }
    end

    def collision_message(base_token, resolved)
      state = resolved ? 'resolved' : 'unresolved'
      "Safe-token collision #{state} for #{base_token}"
    end
  end
end
