# frozen_string_literal: true

# Composite delegated-type holder fixture.
class P204Entry < ApplicationRecord
  delegated_type :entryable,
                 types: %w[P204Post],
                 foreign_key: %i[entryable_region_code entryable_id]
end
