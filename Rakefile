# frozen_string_literal: true

require 'bundler/gem_tasks'
require 'rubocop/rake_task'
require 'rspec/core/rake_task'
require 'yaml'

BUNDLE_AUDIT_COMMAND = %w[bundle exec bundler-audit check --no-update].freeze unless defined?(BUNDLE_AUDIT_COMMAND)
BUNDLE_AUDIT_UPDATE_COMMAND = %w[bundle exec bundler-audit update].freeze unless defined?(BUNDLE_AUDIT_UPDATE_COMMAND)

def git_ref?(ref)
  system('git', 'rev-parse', '--verify', '--quiet', "#{ref}^{commit}", out: File::NULL)
end

def undercover_compare_ref(default_ref)
  env_ref = ENV.fetch('UNDERCOVER_COMPARE', nil)
  return env_ref if env_ref && git_ref?(env_ref)

  [default_ref, 'origin/main', 'main', 'HEAD^'].find { |ref| git_ref?(ref) }
end

RSpec::Core::RakeTask.new(:spec)

RuboCop::RakeTask.new(:rubocop)

namespace :rubocop do
  RuboCop::RakeTask.new(:autocorrect_all) do |task|
    task.options = ['--autocorrect-all']
  end

  desc 'Autocorrect Ruby style offenses'
  task auto_correct: :autocorrect_all
end

namespace :bundle do
  desc 'Audit Gemfile.lock for vulnerable dependencies and insecure sources'
  task :audit do
    sh(*BUNDLE_AUDIT_COMMAND)
  end

  namespace :audit do
    desc 'Refresh ruby-advisory-db for Bundler Audit'
    task :update do
      sh(*BUNDLE_AUDIT_UPDATE_COMMAND)
    end
  end
end

desc 'Run coverage and changed-code coverage checks'
task coverage: :spec do
  config = YAML.safe_load_file('.undercover.yml')
  compare_ref = undercover_compare_ref(config.fetch('compare'))
  abort 'No usable Undercover compare ref found' unless compare_ref

  sh(
    'bundle', 'exec', 'undercover',
    '--simplecov', config.fetch('simplecov'),
    '--compare', compare_ref,
    '--include-files', config.fetch('include_files'),
    '--exclude-files', config.fetch('exclude_files'),
    '--max-warnings', config.fetch('max_warnings').to_s
  )
end

task default: %i[rubocop spec bundle:audit coverage]
