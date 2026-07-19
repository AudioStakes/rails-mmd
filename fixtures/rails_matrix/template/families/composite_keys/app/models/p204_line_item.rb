# frozen_string_literal: true

# Dual primary/foreign-key and through-hop fixture.
class P204LineItem < ApplicationRecord
  self.primary_key = %i[shop_region_code order_code]

  belongs_to :p204_order,
             foreign_key: %i[shop_region_code order_code],
             inverse_of: :p204_line_items
end
