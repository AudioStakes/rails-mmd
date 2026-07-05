# frozen_string_literal: true

require 'aruba/rspec'
require 'climate_control'

RSpec.configure do |config|
  config.disable_monkey_patching!
  config.order = :random
  Kernel.srand config.seed

  config.around(:each, :env) do |example|
    ClimateControl.modify(example.metadata.fetch(:env)) do
      example.run
    end
  end

  config.before(:suite) do
    focused = RSpec.world.all_examples.select { |example| example.metadata[:focus] }
    next if focused.empty?

    locations = focused.map(&:location).join(', ')
    raise "Focused specs are not allowed: #{locations}"
  end

  config.expect_with :rspec do |expectations|
    expectations.syntax = :expect
  end
end
