# frozen_string_literal: true

require 'open3'
require 'rails_mmd/cli'
require 'rails_mmd/version'

RSpec.describe RailsMmd::CLI do
  def run_cli(*)
    Open3.capture3('bundle', 'exec', 'exe/rails-mmd', *)
  end

  describe '--help' do
    subject(:result) { run_cli('--help') }

    it 'succeeds' do
      expect(result[2]).to be_success
    end

    it 'writes no error output' do
      expect(result[1]).to be_empty
    end

    it 'prints only help and version commands' do
      expect(result[0]).to include('rails-mmd help [COMMAND]', 'rails-mmd version')
    end

    it 'does not expose P0 command or option names' do
      expect(result[0]).not_to match(/generate|--config|--output-dir|--domain|--format|--fail-on-warning/)
    end
  end

  describe '--version' do
    subject(:result) { run_cli('--version') }

    it 'succeeds' do
      expect(result[2]).to be_success
    end

    it 'writes no error output' do
      expect(result[1]).to be_empty
    end

    it 'prints the version' do
      expect(result[0]).to eq("#{RailsMmd::VERSION}\n")
    end
  end

  it 'rejects the future generate command' do
    _stdout, stderr, = run_cli('generate')

    expect(stderr).to include('Could not find command "generate".')
  end

  it 'returns failure for the future generate command' do
    _stdout, _stderr, status = run_cli('generate')

    expect(status).not_to be_success
  end
end
