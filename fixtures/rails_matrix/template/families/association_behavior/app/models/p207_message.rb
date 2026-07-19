# frozen_string_literal: true

# Concrete delegated-type behavior fixture target.
class P207Message < ApplicationRecord
  has_one :entry, as: :entryable, class_name: 'P207Entry', dependent: :nullify
end
