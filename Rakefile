# frozen_string_literal: true

require 'bundler/gem_tasks'
require 'rubocop/rake_task'
require 'rspec/core/rake_task'
require 'yaml'

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
    sh 'bundle exec bundler-audit check --update'
  end
end

desc 'Run coverage and changed-code coverage checks'
task coverage: :spec do
  config = YAML.safe_load_file('.undercover.yml')
  sh [
    'bundle exec undercover',
    '--simplecov', config.fetch('simplecov'),
    '--compare', ENV.fetch('UNDERCOVER_COMPARE', config.fetch('compare')),
    '--include-files', config.fetch('include_files'),
    '--exclude-files', config.fetch('exclude_files'),
    '--max-warnings', config.fetch('max_warnings').to_s
  ].join(' ')
end

task default: %i[rubocop spec bundle:audit coverage]
