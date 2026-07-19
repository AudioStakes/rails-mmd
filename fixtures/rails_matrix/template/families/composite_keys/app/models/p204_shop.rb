# frozen_string_literal: true

# Composite direct, through, scoped, and polymorphic owner fixture.
class P204Shop < ApplicationRecord
  self.primary_key = %i[region_code shop_code]

  has_many :p204_orders,
           -> { raise 'scope execution is forbidden' },
           foreign_key: %i[shop_region_code shop_code],
           inverse_of: :p204_shop
  has_many :p204_line_items, through: :p204_orders
  has_many :p204_attachments,
           as: :attachable,
           foreign_key: %i[attachable_region_code attachable_id],
           inverse_of: :attachable
end
