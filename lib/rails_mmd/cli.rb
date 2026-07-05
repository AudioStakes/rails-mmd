# frozen_string_literal: true

require 'thor'
require_relative 'version'

module RailsMmd
  # Minimal Thor shell for smokeable help and version output.
  class CLI < Thor
    package_name 'rails-mmd'
    remove_command :tree
    default_task :help

    def self.exit_on_failure?
      true
    end

    desc 'version', 'Print rails-mmd version'
    map '--version' => :version, '-v' => :version
    def version
      say RailsMmd::VERSION
    end
  end
end
