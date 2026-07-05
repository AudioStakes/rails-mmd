# frozen_string_literal: true

module RailsMmd
  # Normalizes diagnostic subject identifiers without treating them as free text.
  module SubjectIds
    PATTERN = /\A[A-Za-z0-9_:.]+\z/

    module_function

    def normalize(value, code:)
      subject_id = value&.to_s
      return subject_id if subject_id.nil? || subject_id.match?(PATTERN)

      raise ArgumentError, "invalid diagnostic subject_id for #{code}"
    end
  end
end
