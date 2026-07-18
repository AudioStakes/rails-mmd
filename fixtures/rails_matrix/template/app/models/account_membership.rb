# frozen_string_literal: true

# Singular through fixture join model.
class AccountMembership < ApplicationRecord
  belongs_to :author
  belongs_to :account
end
