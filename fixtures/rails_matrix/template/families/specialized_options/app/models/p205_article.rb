# frozen_string_literal: true

# Delegated-type concrete custom referenced-key target fixture.
class P205Article < ApplicationRecord
  has_one :p205_entry,
          as: :entryable,
          foreign_key: :record_code,
          foreign_type: :record_kind,
          primary_key: :slug,
          inverse_of: :entryable
end
