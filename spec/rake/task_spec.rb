# frozen_string_literal: true

require 'rake'

RSpec.describe Rake::Task do
  def expected_undercover_command
    [
      { 'SIMPLECOV_NO_DEFAULTS' => 'true' },
      'bundle', 'exec', 'undercover',
      '--simplecov', 'coverage/undercover.json',
      '--include-files', 'lib/**/*.rb,exe/rails-mmd,tooling/**/*.rb',
      '--exclude-files', YAML.safe_load_file('.undercover.yml').fetch('exclude_files'),
      '--max-warnings', '20',
      '--compare', RailsMmd::ToolingTasks.undercover_compare_ref('HEAD~1')
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
    expect(described_class[:default].prerequisites).to eq(%w[rubocop spec bundle:audit coverage verify:rails_matrix])
  end

  it 'defines an explicit autocorrect task' do
    expect(described_class.task_defined?('rubocop:auto_correct')).to be(true)
  end

  it 'keeps autocorrect out of read-only diagnostics' do
    expect(described_class[:default].prerequisites).not_to include('rubocop:auto_correct')
  end

  it 'checks bundle audit without updating advisory data' do
    expect(RailsMmd::ToolingTasks::BUNDLE_AUDIT_COMMAND).to eq(%w[bundle exec bundler-audit check --no-update])
  end

  describe 'bundle:audit' do
    let(:task) { described_class['bundle:audit'] }
    let(:command_runner) { task.actions.first.binding.receiver }
    let(:audit_command) { RailsMmd::ToolingTasks::BUNDLE_AUDIT_COMMAND }
    let(:lockfiles) do
      %w[Gemfile.lock fixtures/rails_matrix/bundles/7.2/Gemfile.lock
         fixtures/rails_matrix/bundles/8.1/Gemfile.lock]
    end

    before { allow(command_runner).to receive(:sh) }

    it 'audits the root and every Rails fixture lockfile' do
      task.invoke
      lockfiles.each do |lockfile|
        expect(command_runner).to have_received(:sh).with(*audit_command, '--gemfile-lock', lockfile).ordered
      end
    end

    it 'fails when a Rails fixture audit fails' do
      allow(command_runner).to receive(:sh)
        .with(*audit_command, '--gemfile-lock', lockfiles[1]).and_raise(RuntimeError, 'fixture audit failed')

      expect { task.invoke }.to raise_error(RuntimeError, 'fixture audit failed')
    end
  end

  it 'defines explicit advisory data refresh' do
    expect(described_class.task_defined?('bundle:audit:update')).to be(true)
  end

  it 'builds coverage command as argv-safe undercover options' do
    command = RailsMmd::ToolingTasks.undercover_command(YAML.safe_load_file('.undercover.yml'))

    expect(command).to match_array(expected_undercover_command)
  end
end
