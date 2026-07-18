# frozen_string_literal: true

# Nested through fixture target.
class Label < ApplicationRecord
  has_many :labelings
  has_many :posts, through: :labelings
end
