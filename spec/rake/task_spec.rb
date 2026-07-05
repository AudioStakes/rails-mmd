# frozen_string_literal: true

require 'rake'

RSpec.describe Rake::Task do
  def expected_undercover_command
    [
      'bundle', 'exec', 'undercover',
      '--simplecov', 'coverage/coverage.json',
      '--include-files', 'lib/**/*.rb,exe/rails-mmd,Rakefile',
      '--exclude-files', 'spec/**/*.rb',
      '--max-warnings', '20',
      '--compare', undercover_compare_ref('HEAD~1')
    ]
  end

  around do |example|
    previous_application = Rake.application
    Rake.application = Rake::Application.new
    load File.expand_path('../../Rakefile', __dir__)

    example.run
  ensure
    Rake.application = previous_application
  end

  it 'runs read-only diagnostics by default' do
    expect(described_class[:default].prerequisites).to eq(%w[rubocop spec bundle:audit coverage])
  end

  it 'defines an explicit autocorrect task' do
    expect(described_class.task_defined?('rubocop:auto_correct')).to be(true)
  end

  it 'keeps autocorrect out of read-only diagnostics' do
    expect(described_class[:default].prerequisites).not_to include('rubocop:auto_correct')
  end

  it 'checks bundle audit without updating advisory data' do
    expect(BUNDLE_AUDIT_COMMAND).to eq(%w[bundle exec bundler-audit check --no-update])
  end

  it 'defines explicit advisory data refresh' do
    expect(described_class.task_defined?('bundle:audit:update')).to be(true)
  end

  it 'builds coverage command as argv-safe undercover options' do
    command = undercover_command(YAML.safe_load_file('.undercover.yml'))

    expect(command).to match_array(expected_undercover_command)
  end
end
