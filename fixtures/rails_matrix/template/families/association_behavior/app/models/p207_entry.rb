# frozen_string_literal: true

# Delegated-type behavior fixture root.
class P207Entry < ApplicationRecord
  delegated_type :entryable,
                 types: %w[P207Message], dependent: :destroy, touch: true,
                 counter_cache: :entries_count
end
