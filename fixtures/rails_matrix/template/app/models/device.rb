# frozen_string_literal: true

# Ruby inheritance with STI disabled even though the table has a type column.
class Device < ApplicationRecord
  self.inheritance_column = :_type_disabled
end
