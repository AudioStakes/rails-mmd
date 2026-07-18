# frozen_string_literal: true

# One-hop through fixture join model.
class Membership < ApplicationRecord
  belongs_to :author
  belongs_to :team
end
