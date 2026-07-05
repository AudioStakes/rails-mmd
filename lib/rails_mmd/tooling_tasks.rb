# frozen_string_literal: true

module RailsMmd
  # Shared command builders for repository Rake tooling.
  module ToolingTasks
    BUNDLE_AUDIT_COMMAND = %w[bundle exec bundler-audit check --no-update].freeze
    BUNDLE_AUDIT_UPDATE_COMMAND = %w[bundle exec bundler-audit update].freeze

    module_function

    def git_ref?(ref)
      system('git', 'rev-parse', '--verify', '--quiet', "#{ref}^{commit}", out: File::NULL)
    end

    def undercover_compare_ref(default_ref)
      env_ref = ENV.fetch('UNDERCOVER_COMPARE', nil)
      return env_ref if env_ref && git_ref?(env_ref)

      [default_ref, 'origin/main', 'main', 'HEAD^'].find { |ref| git_ref?(ref) }
    end

    def undercover_command(config)
      compare_ref = undercover_compare_ref(config.fetch('compare'))
      abort 'No usable Undercover compare ref found' unless compare_ref

      [
        { 'SIMPLECOV_NO_DEFAULTS' => 'true' },
        'bundle', 'exec', 'undercover',
        *undercover_options(config, compare_ref)
      ]
    end

    def undercover_options(config, compare_ref)
      [
        '--simplecov', config.fetch('simplecov'),
        '--compare', compare_ref,
        '--include-files', config.fetch('include_files'),
        '--exclude-files', config.fetch('exclude_files'),
        '--max-warnings', config.fetch('max_warnings').to_s
      ]
    end
  end
end
