# frozen_string_literal: true

# Fixture owner model.
class Author < ApplicationRecord
  has_one :profile
  has_many :posts, dependent: :destroy, inverse_of: :author
  has_many :drafts
  has_many :notes, inverse_of: false
  has_many :memberships
  has_many :teams, through: :memberships
  has_many :partnerships
  has_many :collaborators, through: :partnerships
  has_one :account_membership
  has_one :account, through: :account_membership
  has_many :labels, -> { raise 'scope execution is forbidden' }, through: :posts
  has_and_belongs_to_many :tags, -> { raise 'scope execution is forbidden' }
end
