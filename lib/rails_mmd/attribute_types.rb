# frozen_string_literal: true

module RailsMmd
  # Normalizes DB/Rails attribute type hints for Mermaid-facing render plans.
  module AttributeTypes
    SUPPORTED_TYPES = %w[
      bigint
      boolean
      date
      datetime
      decimal
      float
      integer
      string
      text
      time
      unknown
    ].freeze

    module_function

    def normalize(value)
      type = value.to_s.downcase.gsub(/[^a-z0-9]+/, '_').gsub(/\A_+|_+\z/, '')
      return type if SUPPORTED_TYPES.include?(type)

      'unknown'
    end
  end
end
