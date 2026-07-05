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
                   diagnostics: Diagnostics.new)
      @project_root = Pathname(project_root).expand_path
      @kernel = kernel
      @rails_provider = rails_provider
      @diagnostics = diagnostics
    end

    def boot
      kernel.load(environment_path.to_s)
      application = rails_provider.call.application
      eager_load(application)
      Result.new(application: application, diagnostics: [], exit_code: 0)
    rescue EagerLoadError => e
      failure('RAILS_EAGER_LOAD_FAILED', e.cause || e)
    rescue StandardError => e
      failure('RAILS_LOAD_FAILED', e)
    end

    private

    class EagerLoadError < StandardError
    end

    attr_reader :diagnostics, :kernel, :project_root, :rails_provider

    def environment_path
      project_root.join('config/environment.rb')
    end

    def eager_load(application)
      application.eager_load! if application.respond_to?(:eager_load!)
    rescue StandardError => e
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
