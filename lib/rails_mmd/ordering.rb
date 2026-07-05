# frozen_string_literal: true

module RailsMmd
  # Stable ordering helpers used by later pipeline slices.
  module Ordering
    module_function

    def by_key(records, key)
      records.sort_by { |record| record.fetch(key) }
    end

    def diagnostics(records)
      records.sort_by do |diagnostic|
        [
          diagnostic.fetch('severity'),
          diagnostic.fetch('phase'),
          diagnostic.fetch('code'),
          diagnostic.fetch('subject_id').to_s,
          diagnostic.fetch('diagnostic_id')
        ]
      end
    end
  end
end
