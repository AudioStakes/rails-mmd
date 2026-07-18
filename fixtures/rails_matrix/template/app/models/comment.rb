# frozen_string_literal: true

# Polymorphic holder fixture.
class Comment < ApplicationRecord
  belongs_to :commentable, polymorphic: true
end
