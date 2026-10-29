# frozen_string_literal: true

require 'bundler'
require 'open3'
require 'rbconfig'
require 'rubygems/package'
require 'rubygems/user_interaction'
require 'tmpdir'

RSpec.describe Gem::Package do
  def with_packaged_cli
    Dir.mktmpdir('rails-mmd-package') do |directory|
      archive = File.join(directory, 'rails-mmd.gem')
      specification = Gem::Specification.load('rails-mmd.gemspec')
      Gem::DefaultUserInteraction.use_ui(Gem::SilentUI.new) do
        described_class.build(specification, false, true, archive)
      end
      packaged_root = File.join(directory, 'extracted')
      described_class.new(archive).extract_files(packaged_root)
      yield packaged_root, directory
    end
  end

  def run_packaged_cli(packaged_root, directory, *arguments)
    environment = Bundler.unbundled_env.merge('RUBYLIB' => nil, 'RUBYOPT' => nil)
    Open3.capture3(
      environment, RbConfig.ruby, '-I', File.join(packaged_root, 'lib'),
      File.join(packaged_root, 'exe/rails-mmd'), *arguments, chdir: directory, unsetenv_others: true
    )
  end

  it 'runs the packaged executable outside the checkout without Bundler' do
    with_packaged_cli do |packaged_root, directory|
      stdout, stderr, status = run_packaged_cli(packaged_root, directory, '--version')

      expect([stdout.strip, stderr, status.exitstatus]).to eq([Gem::Specification.load('rails-mmd.gemspec').version.to_s,
                                                               '', 0])
    end
  end

  it 'excludes repository-only tooling and test fixtures from the archive' do
    with_packaged_cli do |packaged_root, _directory|
      files = Dir.glob('**/*', base: packaged_root)

      expect(files.grep(%r{\A(?:tooling|spec|fixtures)/|lib/rails_mmd/(?:tooling_tasks|verification_runner)\.rb\z}))
        .to be_empty
    end
  end

  it 'loads the packaged schemas and diagnostic catalog when generation fails' do
    with_packaged_cli do |packaged_root, directory|
      stdout, stderr, status = run_packaged_cli(packaged_root, directory, 'generate')

      expect([stdout, stderr, status.exitstatus]).to match(['', include('CONFIG_NOT_FOUND'), 2])
    end
  end
end
