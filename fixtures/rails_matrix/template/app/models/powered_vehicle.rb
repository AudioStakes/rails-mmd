# frozen_string_literal: true

# Abstract boundary that starts a new concrete base-class family below it.
class PoweredVehicle < Vehicle
  self.abstract_class = true
end
