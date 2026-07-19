# frozen_string_literal: true

# Query-constraint has-many child fixture.
class P204Bin < ApplicationRecord
  belongs_to :p204_warehouse,
             foreign_key: %i[region_code warehouse_id],
             inverse_of: :p204_bins
end
