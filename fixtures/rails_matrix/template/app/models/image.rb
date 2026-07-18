# frozen_string_literal: true

# Singular polymorphic candidate fixture.
class Image < ApplicationRecord
  has_one :comment, as: :commentable
end
