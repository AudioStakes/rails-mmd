# frozen_string_literal: true

# Composite polymorphic holder fixture.
class P204Attachment < ApplicationRecord
  belongs_to :attachable,
             polymorphic: true,
             foreign_key: %i[attachable_region_code attachable_id]
end
