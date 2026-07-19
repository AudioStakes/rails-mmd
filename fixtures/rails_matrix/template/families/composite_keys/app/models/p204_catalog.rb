# frozen_string_literal: true

# Composite key containing id inference fixture.
class P204Catalog < ApplicationRecord
  self.primary_key = %i[tenant_id id]

  has_many :p204_catalog_items
end
