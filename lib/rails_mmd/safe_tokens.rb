# frozen_string_literal: true

require 'rails_mmd/canonical_json'
require 'rails_mmd/diagnostics'

module RailsMmd
  # Mermaid-safe token generation and scoped collision resolution.
  class SafeTokens
    TOKEN_KINDS = %w[entity attribute relationship diagnostic comment].freeze
    ARTIFACT_KINDS = %w[er class].freeze

    def initialize(diagnostics: Diagnostics.new)
      @diagnostics = diagnostics
    end

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

    def assign(subjects, scope:)
      validate_scope!(scope)
      grouped = subjects.group_by { |subject| base_token(subject.fetch(:source)) }
      tokens = {}
      collision_diagnostics = assign_groups(grouped, scope, tokens)

      { tokens: tokens, diagnostics: collision_diagnostics }
    end

    private

    attr_reader :diagnostics

    def validate_scope!(scope)
      raise ArgumentError, 'invalid artifact_kind' unless ARTIFACT_KINDS.include?(scope.fetch(:artifact_kind))
      raise ArgumentError, 'invalid token_kind' unless TOKEN_KINDS.include?(scope.fetch(:token_kind))
    end

    def assign_groups(grouped, scope, tokens)
      grouped.filter_map do |base, group|
        if group.one?
          tokens[group.first.fetch(:identity)] = base
          next
        end

        resolved = resolve_group?(scope, base, group, tokens)
        collision_diagnostic(scope, base, group, resolved: resolved)
      end
    end

    def resolve_group?(scope, base, group, tokens)
      suffix_length = 12
      loop do
        return true if merge_unique_candidates?(scope, base, group, tokens, suffix_length)

        suffix_length += 4
        break if suffix_length > 64
      end

      false
    end

    def merge_unique_candidates?(scope, base, group, tokens, suffix_length)
      candidates = collision_candidates(scope, base, group, suffix_length)
      return false unless candidates.values.uniq.length == candidates.length

      tokens.merge!(candidates)
      true
    end

    def collision_candidates(scope, base, group, suffix_length)
      group.to_h do |subject|
        [subject.fetch(:identity), "#{base}_H#{collision_digest(scope, base, subject)[0, suffix_length]}"]
      end
    end

    def collision_digest(scope, base, subject)
      payload = {
        'scope' => {
          'artifact_kind' => scope.fetch(:artifact_kind),
          'domain_id' => scope.fetch(:domain_id),
          'token_kind' => scope.fetch(:token_kind)
        },
        'subject_identity' => subject.fetch(:identity),
        'base_safe_token' => base
      }
      CanonicalJson.digest_sha256(payload).upcase
    end

    def collision_diagnostic(scope, base, group, resolved:)
      diagnostics.build(
        code: 'SAFE_TOKEN_COLLISION',
        subject_id: "#{scope.fetch(:artifact_kind)}:#{scope.fetch(:domain_id)}:#{scope.fetch(:token_kind)}:#{base}",
        message: collision_message(base, resolved),
        severity: resolved ? 'warning' : 'fatal',
        metadata: collision_metadata(scope, base, group, resolved: resolved)
      )
    end

    def collision_metadata(scope, base, group, resolved:)
      {
        artifact_kind: scope.fetch(:artifact_kind),
        domain_id: scope.fetch(:domain_id),
        token_kind: scope.fetch(:token_kind),
        base_safe_token: base,
        collision_subject_count: group.length,
        resolved: resolved
      }
    end

    def collision_message(base, resolved)
      state = resolved ? 'resolved' : 'unresolved'
      "Safe-token collision #{state} for #{base}"
    end
  end
end
