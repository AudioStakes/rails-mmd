# frozen_string_literal: true

# Direct has-one behavior fixture target.
class P207Profile < ApplicationRecord
  belongs_to :account, class_name: 'P207Account', optional: true
end
