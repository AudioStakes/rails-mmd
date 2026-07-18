# frozen_string_literal: true

# Fixture owner model.
class Author < ApplicationRecord
  has_many :posts, dependent: :destroy
end
