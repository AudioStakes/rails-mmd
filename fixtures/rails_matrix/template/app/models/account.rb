# frozen_string_literal: true

# Through fixture target with a singular reverse path.
class Account < ApplicationRecord
  has_one :account_membership
  has_one :author, through: :account_membership
end
