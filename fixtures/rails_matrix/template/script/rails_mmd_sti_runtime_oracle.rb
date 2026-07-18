# frozen_string_literal: true

require 'fileutils'
require 'json'

classes = [
  Admin::Dog,
  Animal,
  Appliance,
  Car,
  Device,
  ElectricCar,
  ElectricVehicle,
  EmailMessage,
  Message,
  Phone,
  PoweredVehicle,
  SportsCar,
  Storefront::Dog,
  Toaster,
  Vehicle
].sort_by(&:name)

projection = classes.map do |klass|
  {
    'ruby_constant' => klass.name,
    'base_class' => klass.base_class.name,
    'table_name' => klass.table_name,
    'inheritance_column' => klass.inheritance_column.to_s,
    'sti_name' => klass.sti_name,
    'abstract_class' => klass.abstract_class?,
    'descends_from_active_record' => klass.descends_from_active_record?
  }
end

output_root = Rails.root.join('tmp/rails_mmd')
FileUtils.mkdir_p(output_root)
File.write(output_root.join('sti_runtime.json'), "#{JSON.pretty_generate(projection)}\n")
