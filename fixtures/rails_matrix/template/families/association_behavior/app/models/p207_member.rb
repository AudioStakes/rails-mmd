# frozen_string_literal: true

# Direct belongs-to behavior fixture owner.
class P207Member < ApplicationRecord
  belongs_to :account,
             class_name: 'P207Account', dependent: :delete, touch: :members_touched_at,
             counter_cache: true
  belongs_to :custom_account,
             class_name: 'P207Account', counter_cache: { active: false, column: :custom_members_count },
             optional: true

  has_many :notes, class_name: 'P207Note', foreign_key: :member_id, dependent: :restrict_with_error
end
