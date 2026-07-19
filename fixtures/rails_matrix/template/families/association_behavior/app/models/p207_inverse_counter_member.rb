# frozen_string_literal: true

# Inverse-only counter-cache false-positive fixture member.
class P207InverseCounterMember < ApplicationRecord
  belongs_to :account,
             class_name: 'P207InverseCounterAccount', foreign_key: :account_id
end
