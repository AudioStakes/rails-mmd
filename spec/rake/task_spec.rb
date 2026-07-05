# frozen_string_literal: true

require 'rake'

RSpec.describe Rake::Task do
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
end
