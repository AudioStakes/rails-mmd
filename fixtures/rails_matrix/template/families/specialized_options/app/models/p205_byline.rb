# frozen_string_literal: true

# Explicit through-source alias join fixture.
class P205Byline < ApplicationRecord
  belongs_to :p205_publication, inverse_of: :p205_bylines
  belongs_to :credited_writer,
             class_name: 'P205Writer',
             foreign_key: :p205_writer_id,
             inverse_of: :p205_bylines
end
