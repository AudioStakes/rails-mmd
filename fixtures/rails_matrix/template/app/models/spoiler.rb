# frozen_string_literal: true

# Target of a subtype-only association that must not create a matrix edge.
class Spoiler < ApplicationRecord
  belongs_to :sports_car, class_name: 'SportsCar', foreign_key: 'vehicle_id', inverse_of: :spoilers
end
