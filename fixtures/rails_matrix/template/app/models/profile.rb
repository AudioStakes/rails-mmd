# frozen_string_literal: true

# Automatic-inverse has-one target.
class Profile < ApplicationRecord
  belongs_to :author
end
