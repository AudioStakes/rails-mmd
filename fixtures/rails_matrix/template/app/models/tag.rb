# frozen_string_literal: true

# Reciprocal HABTM fixture target.
class Tag < ApplicationRecord
  has_and_belongs_to_many :authors
end
