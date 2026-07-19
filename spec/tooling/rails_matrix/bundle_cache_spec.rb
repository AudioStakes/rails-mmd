# frozen_string_literal: true

require 'digest'
require 'fileutils'
require 'pathname'
require 'tmpdir'
require_relative '../../../tooling/rails_matrix'

RSpec.describe RailsMatrix::BundleCache do
  let(:ruby_version) { '4.0.6' }
  let(:rails_series) { '8.1' }
  let(:pair) { RailsMatrix::Pair.new(ruby_version:, rails_series:) }
  let(:root) { Pathname(Dir.mktmpdir('rails-matrix-cache-spec')) }

  before { write_lock(rails_series, "LOCK ONE\n") }

  after { FileUtils.remove_entry(root) if root.exist? }

  def write_lock(series, content)
    path = root.join('fixtures/rails_matrix/bundles', series, 'Gemfile.lock')
    path.dirname.mkpath
    path.write(content)
  end

  it 'keys the repository-local cache by Ruby, Rails series, and lockfile content' do
    digest = Digest::SHA256.hexdigest("LOCK ONE\n")

    expect(described_class.new(root:).path_for(pair)).to eq(
      root.join('.bundle/rails-matrix/gems', ruby_version, "#{rails_series}-#{digest}")
    )
  end

  it 'changes the cache path when the selected lockfile changes' do
    cache = described_class.new(root:)
    original = cache.path_for(pair)

    write_lock(rails_series, "LOCK TWO\n")

    expect(cache.path_for(pair)).not_to eq(original)
  end

  it 'keeps other Rails series in separate cache paths for the same Ruby' do
    write_lock('7.2', "LOCK SEVEN\n")
    other_pair = RailsMatrix::Pair.new(ruby_version:, rails_series: '7.2')
    cache = described_class.new(root:)

    expect(cache.path_for(other_pair)).not_to eq(cache.path_for(pair))
  end

  it 'expands a relative shared cache root against the repository root',
     env: { 'RAILS_MMD_MATRIX_CACHE_ROOT' => '../shared-matrix-cache' } do
    expected_root = root.join('../shared-matrix-cache').expand_path

    expect(described_class.new(root:).path_for(pair).to_s).to start_with("#{expected_root}/")
  end

  it 'rejects an empty shared cache root', env: { 'RAILS_MMD_MATRIX_CACHE_ROOT' => '' } do
    expect { described_class.new(root:).path_for(pair) }
      .to raise_error(RailsMatrix::VerificationError, /must not be empty/)
  end

  it 'reports a missing selected lockfile as a matrix verification error' do
    missing = RailsMatrix::Pair.new(ruby_version:, rails_series: 'missing')

    expect { described_class.new(root:).path_for(missing) }
      .to raise_error(RailsMatrix::VerificationError, /cannot read bundle lockfile/)
  end

  it 'rejects an empty selected lockfile' do
    write_lock(rails_series, '')

    expect { described_class.new(root:).path_for(pair) }
      .to raise_error(RailsMatrix::VerificationError, /bundle lockfile is empty/)
  end
end
