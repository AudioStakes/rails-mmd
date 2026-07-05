# frozen_string_literal: true

require_relative 'lib/rails_mmd/version'

Gem::Specification.new do |spec|
  spec.name = 'rails-mmd'
  spec.version = RailsMmd::VERSION
  spec.authors = ['AudioStakes']
  spec.email = ['engineering@audiostakes.com']

  spec.summary = 'Generate Mermaid diagrams from Rails and ActiveRecord applications.'
  spec.description = 'rails-mmd is a Ruby CLI for generating Mermaid diagrams ' \
                     'from configured Rails/ActiveRecord domains.'
  spec.homepage = 'https://github.com/AudioStakes/rails-mmd'
  spec.license = 'MIT'
  spec.required_ruby_version = Gem::Requirement.new('>= 4.0.5', '< 4.1')

  spec.metadata['homepage_uri'] = spec.homepage
  spec.metadata['source_code_uri'] = "#{spec.homepage}/tree/main"
  spec.metadata['rubygems_mfa_required'] = 'true'

  spec.files = Dir['README.md', 'exe/rails-mmd', 'lib/**/*.rb']
  spec.bindir = 'exe'
  spec.executables = ['rails-mmd']
  spec.require_paths = ['lib']

  spec.add_dependency 'activesupport', '~> 8.1'
  spec.add_dependency 'json-canonicalization', '~> 1.0'
  spec.add_dependency 'json_schemer', '~> 2.5'
  spec.add_dependency 'thor', '~> 1.5'
end
