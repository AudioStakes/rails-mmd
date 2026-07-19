# frozen_string_literal: true

# Inverse-only counter-cache false-positive fixture owner.
class P207InverseCounterAccount < ApplicationRecord
  has_many :members,
           class_name: 'P207InverseCounterMember', foreign_key: :account_id,
           counter_cache: :inverse_named_members_count
end
