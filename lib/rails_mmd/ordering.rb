# frozen_string_literal: true

module RailsMmd
  # Stable ordering helpers used by later pipeline slices.
  module Ordering
    SEVERITY_RANK = { 'fatal' => 0, 'error' => 1, 'warning' => 2 }.freeze

    module_function

    def sort_by_key(records, key)
      records.sort_by { |record| record.fetch(key) }
    end

    def sort_diagnostics(records)
      records.sort_by do |diagnostic|
        [
          SEVERITY_RANK.fetch(diagnostic.fetch('severity')),
          diagnostic.fetch('code'),
          diagnostic.fetch('subject_id').to_s,
          diagnostic.fetch('diagnostic_id')
        ]
      end
    end

    # Backward-compatible method names for the recorded P1 seam.
    def by_key(records, key) = sort_by_key(records, key)

    def diagnostics(records) = sort_diagnostics(records)
  end
end
