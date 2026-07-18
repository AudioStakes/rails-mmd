# frozen_string_literal: true

# Fixture owner model.
class Author < ApplicationRecord
  has_one :profile
  has_many :posts, dependent: :destroy
  has_and_belongs_to_many :tags
end
