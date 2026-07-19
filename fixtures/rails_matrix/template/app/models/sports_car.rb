# frozen_string_literal: true

# Grandchild STI subtype with a subtype-only association.
class SportsCar < Car
  has_many :spoilers, foreign_key: 'vehicle_id', inverse_of: :sports_car
end
