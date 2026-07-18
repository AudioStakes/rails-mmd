# frozen_string_literal: true

# Delegated-type root with custom id, type, and referenced-key columns.
class P205Entry < ApplicationRecord
  delegated_type :entryable,
                 types: %w[P205Article],
                 foreign_key: :record_code,
                 foreign_type: :record_kind,
                 primary_key: :slug,
                 inverse_of: :p205_entry
end
