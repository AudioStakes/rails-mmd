# frozen_string_literal: true

# Fixture model with a supported belongs-to relationship.
class Post < ApplicationRecord
  belongs_to :author, -> { raise 'scope execution is forbidden' }, inverse_of: :posts
  has_many :labelings
  has_many :labels, through: :labelings
  has_many :comments, as: :commentable
end
