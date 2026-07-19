# frozen_string_literal: true

module Admin
  # Namespaced STI subtype whose sti_name demodulizes to Dog.
  class Dog < ::Animal
  end
end
