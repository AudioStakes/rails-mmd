# frozen_string_literal: true

# Explicit through-source alias target fixture.
class P205Writer < ApplicationRecord
  has_many :p205_bylines,
           foreign_key: :p205_writer_id,
           inverse_of: :credited_writer
end
