# frozen_string_literal: true

require 'open3'
require 'rails_mmd/version'

RSpec.describe 'rails-mmd executable' do
  def run_cli(*)
    Open3.capture3('bundle', 'exec', 'exe/rails-mmd', *)
  end

  it 'prints help without exposing P0 commands' do
    stdout, stderr, status = run_cli('--help')

    expect(status).to be_success
    expect(stderr).to be_empty
    expect(stdout).to include('rails-mmd help [COMMAND]')
    expect(stdout).to include('rails-mmd version')
    expect(stdout).not_to include('generate')
    expect(stdout).not_to include('--config')
    expect(stdout).not_to include('--output-dir')
    expect(stdout).not_to include('--domain')
    expect(stdout).not_to include('--format')
    expect(stdout).not_to include('--fail-on-warning')
  end

  it 'prints the version' do
    stdout, stderr, status = run_cli('--version')

    expect(status).to be_success
    expect(stderr).to be_empty
    expect(stdout).to eq("#{RailsMmd::VERSION}\n")
  end

  it 'rejects the future generate command' do
    _stdout, stderr, status = run_cli('generate')

    expect(status).not_to be_success
    expect(stderr).to include('Could not find command "generate".')
  end
end
