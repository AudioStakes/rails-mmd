# frozen_string_literal: true

RSpec.describe Gem::Specification do
  subject(:specification) { described_class.load('rails-mmd.gemspec') }

  it 'supports maintained Ruby versions from 3.3 through 4.0' do
    expect(specification.required_ruby_version).to eq(Gem::Requirement.new('>= 3.3', '< 4.1'))
  end

  it 'does not force the target Rails application to use a specific Active Support series' do
    dependency_names = specification.runtime_dependencies.map(&:name)

    expect(dependency_names).not_to include('activesupport')
  end
end
