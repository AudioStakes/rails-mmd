# frozen_string_literal: true

# Explicit through-source alias owner fixture.
class P205Publication < ApplicationRecord
  has_many :p205_bylines, inverse_of: :p205_publication
  has_many :contributors,
           through: :p205_bylines,
           source: :credited_writer
end
