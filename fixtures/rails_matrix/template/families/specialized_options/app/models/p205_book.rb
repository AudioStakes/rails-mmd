# frozen_string_literal: true

# Specialized polymorphic has-many inverse fixture.
class P205Book < ApplicationRecord
  has_many :p205_asset_links,
           as: :resource,
           foreign_key: :resource_code,
           foreign_type: :resource_kind,
           primary_key: :catalog_code,
           inverse_of: :resource
end
