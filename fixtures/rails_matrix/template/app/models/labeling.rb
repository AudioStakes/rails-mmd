# frozen_string_literal: true

# Nested through fixture join model.
class Labeling < ApplicationRecord
  belongs_to :post
  belongs_to :label
end
