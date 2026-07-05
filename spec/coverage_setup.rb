# frozen_string_literal: true

require 'coverage'
require 'coverage.so'
require 'simplecov/no_defaults'
require 'undercover/simplecov_formatter'

SimpleCov.const_set(:Coverage, Coverage) unless SimpleCov.const_defined?(:Coverage, false)
SimpleCov::Configuration.const_set(:Coverage, Coverage) unless SimpleCov::Configuration.const_defined?(:Coverage, false)

SimpleCov.formatter = SimpleCov::Formatter::Undercover

SimpleCov.start do
  add_filter '/spec/'
end
