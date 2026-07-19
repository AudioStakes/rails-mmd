# frozen_string_literal: true

# Custom-key and custom-type polymorphic holder fixture.
class P205AssetLink < ApplicationRecord
  belongs_to :p205_collection, inverse_of: :p205_asset_links
  belongs_to :resource,
             polymorphic: true,
             foreign_key: :resource_code,
             foreign_type: :resource_kind,
             primary_key: :catalog_code
end
