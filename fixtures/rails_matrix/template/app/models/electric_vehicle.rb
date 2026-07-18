# frozen_string_literal: true

# Concrete post-boundary STI base with its own physical table.
class ElectricVehicle < PoweredVehicle
  self.table_name = 'electric_vehicles'
end
