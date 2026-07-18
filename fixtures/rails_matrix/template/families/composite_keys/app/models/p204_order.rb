# frozen_string_literal: true

# Composite direct and polymorphic target fixture.
class P204Order < ApplicationRecord
  self.primary_key = %i[shop_region_code order_code]

  belongs_to :p204_shop,
             foreign_key: %i[shop_region_code shop_code],
             inverse_of: :p204_orders
  has_many :p204_line_items,
           foreign_key: %i[shop_region_code order_code],
           inverse_of: :p204_order
  has_many :p204_attachments,
           as: :attachable,
           foreign_key: %i[attachable_region_code attachable_id],
           inverse_of: :attachable
end
