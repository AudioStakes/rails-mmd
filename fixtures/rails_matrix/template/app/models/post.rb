# frozen_string_literal: true

# Fixture model with a supported belongs-to relationship.
class Post < ApplicationRecord
  belongs_to :author
end
