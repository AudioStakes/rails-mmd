# frozen_string_literal: true

# Scalar-inferred child of an id-containing composite fixture.
class P204CatalogItem < ApplicationRecord
  belongs_to :p204_catalog
end
