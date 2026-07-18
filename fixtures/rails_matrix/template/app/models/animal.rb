# frozen_string_literal: true

# Namespaced STI base that demodulizes discriminator values.
class Animal < ApplicationRecord
  self.store_full_sti_class = false
end
