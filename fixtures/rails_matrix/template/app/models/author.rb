# frozen_string_literal: true

# Fixture owner model.
class Author < ApplicationRecord
  has_one :profile
  has_many :posts, dependent: :destroy, inverse_of: :author
  has_many :drafts
  has_many :notes, inverse_of: false
  has_and_belongs_to_many :tags
end
