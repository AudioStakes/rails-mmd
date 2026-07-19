# frozen_string_literal: true

# Query-constraint has-one child fixture.
class P204WarehouseProfile < ApplicationRecord
  belongs_to :p204_warehouse,
             foreign_key: %i[region_code warehouse_id],
             inverse_of: :p204_warehouse_profile
end
