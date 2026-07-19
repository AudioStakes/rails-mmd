# frozen_string_literal: true

module RailsMmd
  # Maps diagnostics to the public P0 process exit contract.
  module ExitPolicy
    EXIT_CODE_BY_DIAGNOSTIC_CODE = {
      'MERMAID_SERIALIZATION_FAILED' => 3,
      'SAFE_TOKEN_COLLISION' => 3,
      'OUTPUT_WRITE_FAILED' => 4,
      'INTERNAL_ERROR' => 99
    }.freeze
    BLOCKING_SEVERITIES = %w[fatal error].freeze

    module_function

    def exit_code(diagnostics, fail_on_warning: false)
      blocking = diagnostics.select { |diagnostic| BLOCKING_SEVERITIES.include?(diagnostic.fetch('severity')) }
      if blocking.empty?
        return 1 if fail_on_warning && diagnostics.any? { |diagnostic| diagnostic.fetch('severity') == 'warning' }

        return 0
      end

      blocking.map { |diagnostic| EXIT_CODE_BY_DIAGNOSTIC_CODE.fetch(diagnostic.fetch('code'), 2) }.max
    end
  end
end
