# frozen_string_literal: true

# Inverse-free direct self join.
class Employee < ApplicationRecord
  has_many :reports, class_name: 'Employee', foreign_key: 'manager_id'
end
