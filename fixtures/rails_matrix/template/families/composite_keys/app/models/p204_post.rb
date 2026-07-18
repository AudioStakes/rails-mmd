# frozen_string_literal: true

# Composite delegated-type concrete target fixture.
class P204Post < ApplicationRecord
  self.primary_key = %i[region_code post_code]

  has_one :p204_entry,
          as: :entryable,
          foreign_key: %i[entryable_region_code entryable_id],
          inverse_of: :entryable
end
