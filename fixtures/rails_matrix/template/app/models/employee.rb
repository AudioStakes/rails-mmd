# frozen_string_literal: true

# Explicit-inverse direct self join.
class Employee < ApplicationRecord
  belongs_to :manager, class_name: 'Employee', optional: true, inverse_of: :reports
  has_many :reports, class_name: 'Employee', foreign_key: 'manager_id', inverse_of: :manager
end
