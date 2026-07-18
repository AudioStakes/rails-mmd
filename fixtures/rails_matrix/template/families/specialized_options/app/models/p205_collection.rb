# frozen_string_literal: true

# Typed polymorphic through-source owner fixture.
class P205Collection < ApplicationRecord
  has_many :p205_asset_links, inverse_of: :p205_collection
  has_many :p205_books,
           through: :p205_asset_links,
           source: :resource,
           source_type: 'P205Book'
end
