# frozen_string_literal: true

require 'rails_mmd/diagnostics'

module RailsMmd
  # Boots a host Rails app and eager-loads it through explicit, testable paths.
  # rubocop:disable Metrics/MethodLength
  class RailsLoader
    Result = Struct.new(:application, :diagnostics, :exit_code, keyword_init: true) do
      def success?
        diagnostics.empty?
      end
    end

    EXIT_CONTRACT_ERROR = 2

    def initialize(project_root:, kernel: Kernel, rails_provider: -> { Object.const_get(:Rails) },
                   diagnostics: Diagnostics.new, bundler: (Bundler if defined?(Bundler)))
      @project_root = Pathname(project_root).expand_path
      @kernel = kernel
      @rails_provider = rails_provider
      @diagnostics = diagnostics
      @bundler = bundler
    end

    def boot
      validate_bundle_context!
      kernel.load(environment_path.to_s)
      application = rails_provider.call.application
      eager_load(application)
      Result.new(application: application, diagnostics: [], exit_code: 0)
    rescue EagerLoadError => e
      failure('RAILS_EAGER_LOAD_FAILED', e.cause || e)
    rescue LoadError, SyntaxError, StandardError => e
      failure('RAILS_LOAD_FAILED', e)
    end

    private

    class EagerLoadError < StandardError
    end

    class BundleContextError < StandardError
    end

    attr_reader :bundler, :diagnostics, :kernel, :project_root, :rails_provider

    def environment_path
      project_root.join('config/environment.rb')
    end

    def validate_bundle_context!
      app_gemfile = project_root.join('Gemfile')
      return unless app_gemfile.file?

      current_gemfile = current_bundle_gemfile
      return if current_gemfile && Pathname(current_gemfile).expand_path == app_gemfile

      raise BundleContextError,
            'rails-mmd must be run inside the target Rails application bundle'
    end

    def current_bundle_gemfile
      return unless bundler.respond_to?(:default_gemfile)

      bundler.default_gemfile
    rescue LoadError, StandardError
      nil
    end

    def eager_load(application)
      raise EagerLoadError, 'Rails application does not expose eager_load!' unless application.respond_to?(:eager_load!)

      application.eager_load! if application.respond_to?(:eager_load!)
    rescue LoadError, SyntaxError, StandardError => e
      raise EagerLoadError, e.message
    end

    def failure(code, exception)
      Result.new(
        application: nil,
        diagnostics: [
          diagnostics.build(
            code: code,
            message: exception.message,
            subject_id: 'rails',
            metadata: diagnostics.exception_metadata(exception)
          )
        ],
        exit_code: EXIT_CONTRACT_ERROR
      )
    end
  end
  # rubocop:enable Metrics/MethodLength
end
