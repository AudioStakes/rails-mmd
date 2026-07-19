# frozen_string_literal: true

# Specialized polymorphic has-one inverse fixture.
class P205Cover < ApplicationRecord
  has_one :p205_asset_link,
          as: :resource,
          foreign_key: :resource_code,
          foreign_type: :resource_kind,
          primary_key: :catalog_code,
          inverse_of: :resource
end
