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
  spec.required_ruby_version = '>= 4.0.5'

  spec.metadata['homepage_uri'] = spec.homepage
  spec.metadata['source_code_uri'] = spec.homepage
  spec.metadata['rubygems_mfa_required'] = 'true'

  spec.files = Dir.chdir(__dir__) do
    `git ls-files -z`.split("\x0").reject do |file|
      file.start_with?('.git', '.serena/', 'tmp/', 'log/')
    end
  end
  spec.bindir = 'exe'
  spec.executables = ['rails-mmd']
  spec.require_paths = ['lib']

  spec.add_runtime_dependency 'activesupport'
  spec.add_runtime_dependency 'json-canonicalization'
  spec.add_runtime_dependency 'json_schemer'
  spec.add_runtime_dependency 'thor'
end
