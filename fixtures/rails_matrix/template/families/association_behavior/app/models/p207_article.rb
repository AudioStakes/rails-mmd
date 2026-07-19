# frozen_string_literal: true

# Concrete polymorphic behavior fixture target.
class P207Article < ApplicationRecord
  has_many :attachments, as: :attachable, class_name: 'P207Attachment', dependent: :nullify
end
