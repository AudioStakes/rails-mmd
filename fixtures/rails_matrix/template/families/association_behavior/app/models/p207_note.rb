# frozen_string_literal: true

# Through behavior fixture target.
class P207Note < ApplicationRecord
  belongs_to :member, class_name: 'P207Member'
end
