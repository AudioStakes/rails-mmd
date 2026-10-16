# frozen_string_literal: true

RSpec.describe Gem::Specification do
  subject(:specification) { described_class.load('rails-mmd.gemspec') }

  it 'supports maintained Ruby versions from 3.3 through 4.0' do
    expect(specification.required_ruby_version).to eq(Gem::Requirement.new('>= 3.3', '< 4.1'))
  end

  it 'declares the MIT license' do
    expect(specification.license).to eq('MIT')
  end

  it 'packages the license and user guides with the gem' do
    expect(specification.files).to include(
      'LICENSE', 'README.md', 'CHANGELOG.md', 'SECURITY.md', 'docs/usage.md',
      'docs/active-record-association-support.md'
    )
  end

  it 'links to the source and documentation for the packaged release' do
    expect(specification.metadata).to include(
      'source_code_uri' => "https://github.com/AudioStakes/rails-mmd/tree/v#{specification.version}",
      'documentation_uri' => "https://github.com/AudioStakes/rails-mmd/blob/v#{specification.version}/docs/usage.md",
      'changelog_uri' => "https://github.com/AudioStakes/rails-mmd/blob/v#{specification.version}/CHANGELOG.md"
    )
  end

  it 'restricts publication to RubyGems.org with multifactor authentication' do
    expect(specification.metadata).to include(
      'allowed_push_host' => 'https://rubygems.org',
      'rubygems_mfa_required' => 'true'
    )
  end

  it 'does not force the target Rails application to use a specific Active Support series' do
    dependency_names = specification.runtime_dependencies.map(&:name)

    expect(dependency_names).not_to include('activesupport')
  end
end
