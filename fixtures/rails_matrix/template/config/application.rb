# frozen_string_literal: true

require 'rails'
require 'active_record/railtie'

module RailsMatrixFixture
  # Smallest common Rails application surface needed by rails-mmd.
  class Application < Rails::Application
    config.root = Pathname(__dir__).join('..').expand_path
    config.eager_load = true
    config.logger = Logger.new(nil)
    config.secret_key_base = 'rails-mmd-matrix-fixture-secret-key-base'
  end
end
