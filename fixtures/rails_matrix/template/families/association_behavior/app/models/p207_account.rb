# frozen_string_literal: true

# Reciprocal and through behavior fixture owner.
class P207Account < ApplicationRecord
  has_many :members,
           class_name: 'P207Member', foreign_key: :account_id, dependent: :destroy
  has_one :profile,
          class_name: 'P207Profile', foreign_key: :account_id,
          dependent: :nullify, touch: :profile_touched_at
  has_many :notes, through: :members, source: :notes, dependent: :delete_all
  has_one :latest_note, through: :members, source: :notes,
                        dependent: :destroy, touch: :latest_note_touched_at
end
