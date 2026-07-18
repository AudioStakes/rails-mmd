# frozen_string_literal: true

# One-hop through fixture target.
class Team < ApplicationRecord
  has_many :memberships
  has_many :authors, through: :memberships
end
