# frozen_string_literal: true

# Model-level query-constraint owner fixture.
class P204Warehouse < ApplicationRecord
  query_constraints :region_code, :id

  has_many :p204_bins,
           foreign_key: %i[region_code warehouse_id],
           inverse_of: :p204_warehouse
  has_one :p204_warehouse_profile,
          foreign_key: %i[region_code warehouse_id],
          inverse_of: :p204_warehouse
end
