# frozen_string_literal: true

# Polymorphic behavior fixture root.
class P207Attachment < ApplicationRecord
  belongs_to :attachable,
             polymorphic: true, dependent: :destroy, touch: true,
             counter_cache: :attachments_count
end
