# frozen_string_literal: true

require 'bundler/gem_tasks'
require 'rails_mmd/tooling_tasks'
require 'rubocop/rake_task'
require 'rspec/core/rake_task'
require 'yaml'

RSpec::Core::RakeTask.new(:spec)

RuboCop::RakeTask.new(:rubocop)

namespace :rubocop do
  Rake::Task['rubocop:auto_correct'].clear if Rake::Task.task_defined?('rubocop:auto_correct')

  desc 'Autocorrect Ruby style offenses'
  task :auto_correct do
    sh 'bundle', 'exec', 'rubocop', '--autocorrect-all'
  end
end

namespace :bundle do
  desc 'Audit Gemfile.lock for vulnerable dependencies and insecure sources'
  task :audit do
    sh(*RailsMmd::ToolingTasks::BUNDLE_AUDIT_COMMAND)
  end

  namespace :audit do
    desc 'Refresh ruby-advisory-db for Bundler Audit'
    task :update do
      sh(*RailsMmd::ToolingTasks::BUNDLE_AUDIT_UPDATE_COMMAND)
    end
  end
end

desc 'Run coverage and changed-code coverage checks'
task coverage: :spec do
  config = YAML.safe_load_file('.undercover.yml')
  sh(*RailsMmd::ToolingTasks.undercover_command(config))
end

task default: %i[rubocop spec bundle:audit coverage]
