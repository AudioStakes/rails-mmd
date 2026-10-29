# frozen_string_literal: true

module RailsMmd
  # Stable diagnostic ordering shared by publication and stderr output.
  module Ordering
    SEVERITY_RANK = { 'fatal' => 0, 'error' => 1, 'warning' => 2 }.freeze

    module_function

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
  end
end
