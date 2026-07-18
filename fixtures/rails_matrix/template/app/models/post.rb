# frozen_string_literal: true

# Fixture model with a supported belongs-to relationship.
class Post < ApplicationRecord
  belongs_to :author, inverse_of: :posts
  has_many :labelings
  has_many :labels, through: :labelings
end
